# Recurring job (see config/recurring.yml) — calls the PM twice a day:
# once at noon covering the morning's interventions, once at 6pm covering
# the afternoon's. Each call only reports on interventions from its own
# half-day window.
class DailySummaryCallJob < ApplicationJob
  queue_as :default

  # force: true skips the "nothing to report" guard — used by the PM's
  # manual "trigger recap call now" button (DashboardController), so a
  # judge testing outside the noon/6pm schedule can still see the
  # interactive recap call in action.
  def perform(period, date = Date.current, force: false)
    start_hour, end_hour = DailySummaryCall::WINDOWS.fetch(period)
    window_start = date.beginning_of_day + start_hour.hours
    window_end   = date.beginning_of_day + end_hour.hours

    interventions = Intervention.where(started_at: window_start...window_end).to_a
    # Not just "did anything start in this window" — an intervention that's
    # still in_progress (or was cancelled) has nothing to tell the PM yet.
    # Only call if there's something actually reportable (unless forced).
    reportable = interventions.select { |i| i.status.in?(DailySummaryCall::FLAGGED_STATUSES + ["completed"]) }
    return if reportable.empty? && !force

    pm = Pm.first
    unless pm
      Rails.logger.warn("DailySummaryCallJob(#{period}) skipped: no Pm profile set up yet")
      return
    end

    summary_call = DailySummaryCall.create!(date: date, period: period, pm_phone: pm.phone, call_status: "initiated")
    script = CallScripts.daily_summary(period, interventions)

    response = CallEClient.create_call(
      task: script[:task],
      recipient: pm.call_e_recipient,
      result_schema: script[:result_schema],
      metadata: { daily_summary_call_id: summary_call.id, date: date.iso8601, period: period },
      idempotency_key: "daily_summary_#{period}_#{date.iso8601}"
    )

    summary_call.update!(call_e_call_id: response["call_id"], call_status: "in_progress")
  rescue KeyError => e
    Rails.logger.error("DailySummaryCallJob(#{period}) not configured for #{date}: #{e.message}")
  rescue CallEClient::CallEError => e
    Rails.logger.error("DailySummaryCallJob(#{period}) failed for #{date}: #{e.message}")
  end
end
