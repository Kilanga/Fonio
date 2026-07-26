# Runs 30 minutes after an intervention starts (first attempt), or 5 minutes
# after a failed first attempt (retry). See SPEC.md section 5 and 8.
class CheckInCallJob < ApplicationJob
  queue_as :default

  def perform(intervention, attempt: 1)
    return unless intervention.in_progress?
    return unless intervention.technician.consent_given? # safety net, see SPEC.md section 9

    call = intervention.calls.create!(
      call_type: "check_in",
      call_status: "initiated",
      attempt: attempt
    )

    AuditLog.create!(
      intervention: intervention, technician: intervention.technician,
      actor: "system", event_type: "call_initiated",
      details: { call_type: "check_in", attempt: attempt }
    )

    response = CallEClient.create_call(
      to: intervention.technician.phone,
      goal: CallScripts.check_in(intervention),
      metadata: { intervention_id: intervention.id, call_id: call.id, attempt: attempt }
    )

    call.update!(call_e_call_id: response["call_id"], call_status: "in_progress")
  rescue CallEClient::CallEError => e
    Rails.logger.error("CheckInCallJob failed for intervention=#{intervention.id}: #{e.message}")
    AuditLog.create!(
      intervention: intervention, actor: "system", event_type: "call_error",
      details: { call_type: "check_in", error: e.message }
    )
  end
end
