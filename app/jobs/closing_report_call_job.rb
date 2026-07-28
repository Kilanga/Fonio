# Triggered as soon as the technician's "DONE" SMS is received.
class ClosingReportCallJob < ApplicationJob
  queue_as :default

  def perform(intervention)
    return unless intervention.closing_in_progress?
    return unless intervention.technician.consent_given?
    return unless intervention.technician.region.present? && intervention.technician.locale.present?

    call = intervention.calls.create!(call_type: "closing_report", call_status: "initiated")

    AuditLog.create!(
      intervention: intervention, technician: intervention.technician,
      actor: "system", event_type: "call_initiated",
      details: { call_type: "closing_report" }
    )

    script = CallScripts.closing_report(intervention)

    response = CallEClient.create_call(
      task: script[:task],
      recipient: intervention.technician.call_e_recipient,
      result_schema: script[:result_schema],
      metadata: { intervention_id: intervention.id, call_id: call.id },
      idempotency_key: "closing_report_#{intervention.id}"
    )

    call.update!(call_e_call_id: response["call_id"], call_status: "in_progress")
  rescue CallEClient::RateLimitError => e
    Rails.logger.warn("ClosingReportCallJob rate-limited for intervention=#{intervention.id}, retrying in 2min: #{e.message}")
    call.destroy
    self.class.set(wait: 2.minutes).perform_later(intervention)
  rescue CallEClient::CallEError => e
    Rails.logger.error("ClosingReportCallJob failed for intervention=#{intervention.id}: #{e.message}")
    AuditLog.create!(
      intervention: intervention, actor: "system", event_type: "call_error",
      details: { call_type: "closing_report", error: e.message }
    )
  end
end
