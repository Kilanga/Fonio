# Recurring job (see config/recurring.yml) — calls the PM once a day (e.g. 6pm)
# with a spoken briefing of the day's interventions.
class DailySummaryCallJob < ApplicationJob
  queue_as :default

  def perform(date = Date.current)
    interventions = Intervention.where(started_at: date.all_day).to_a
    return if interventions.empty?

    pm_phone = ENV.fetch("PM_PHONE_NUMBER")
    pm_region = ENV.fetch("PM_REGION", "FR")
    pm_locale = ENV.fetch("PM_LOCALE", "fr-FR")

    summary_call = DailySummaryCall.create!(date: date, pm_phone: pm_phone, call_status: "initiated")
    script = CallScripts.daily_summary(date, interventions)

    response = CallEClient.create_call(
      task: script[:task],
      recipient: { phone: pm_phone, region: pm_region, locale: pm_locale },
      result_schema: script[:result_schema],
      metadata: { daily_summary_call_id: summary_call.id, date: date.iso8601 },
      idempotency_key: "daily_summary_#{date.iso8601}"
    )

    summary_call.update!(call_e_call_id: response["call_id"], call_status: "in_progress")
  rescue CallEClient::CallEError => e
    Rails.logger.error("DailySummaryCallJob failed for #{date}: #{e.message}")
  end
end
