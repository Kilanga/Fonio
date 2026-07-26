# Recurring job (see config/schedule.rb) — calls the PM once a day (e.g. 6pm)
# with a spoken briefing of the day's interventions.
class DailySummaryCallJob < ApplicationJob
  queue_as :default

  def perform(date = Date.current)
    interventions = Intervention.where(started_at: date.all_day).to_a
    return if interventions.empty?

    pm_phone = ENV.fetch("PM_PHONE_NUMBER")
    summary_call = DailySummaryCall.create!(date: date, pm_phone: pm_phone, call_status: "initiated")

    response = CallEClient.create_call(
      to: pm_phone,
      goal: CallScripts.daily_summary(date, interventions),
      metadata: { daily_summary_call_id: summary_call.id, date: date.iso8601 }
    )

    summary_call.update!(call_e_call_id: response["call_id"], call_status: "in_progress")
  rescue CallEClient::CallEError => e
    Rails.logger.error("DailySummaryCallJob failed for #{date}: #{e.message}")
  end
end
