# Triggered as soon as the technician's "DONE" SMS is received.
class ClosingReportCallJob < ApplicationJob
  queue_as :default

  def perform(intervention)
    return unless intervention.closing_in_progress?
    return unless intervention.technician.consent_given?

    call = intervention.calls.create!(call_type: "closing_report", call_status: "initiated")

    AuditLog.create!(
      intervention: intervention, technician: intervention.technician,
      actor: "system", event_type: "call_initiated",
      details: { call_type: "closing_report" }
    )

    response = CallEClient.create_call(
      to: intervention.technician.phone,
      goal: CallScripts.closing_report(intervention),
      metadata: { intervention_id: intervention.id, call_id: call.id }
    )

    call.update!(call_e_call_id: response["call_id"], call_status: "in_progress")
  rescue CallEClient::CallEError => e
    Rails.logger.error("ClosingReportCallJob failed for intervention=#{intervention.id}: #{e.message}")
    AuditLog.create!(
      intervention: intervention, actor: "system", event_type: "call_error",
      details: { call_type: "closing_report", error: e.message }
    )
  end
end
