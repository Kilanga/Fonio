# Runs 30 minutes after an intervention starts (first attempt), or 5 minutes
# after a failed first attempt (retry). See SPEC.md section 5 and 8.
class CheckInCallJob < ApplicationJob
  queue_as :default

  def perform(intervention, attempt: 1)
    # Covers the "technician finished in under 30 minutes" case: they'll
    # have already texted DONE (moving the intervention past in_progress)
    # by the time this fires, so we skip the now-pointless check-in call
    # instead of placing one after the fact. Logged so it's visible in the
    # audit trail rather than silently vanishing.
    unless intervention.in_progress?
      AuditLog.create!(
        intervention: intervention, technician: intervention.technician,
        actor: "system", event_type: "check_in_skipped",
        details: { reason: "intervention no longer in_progress (status=#{intervention.status})", attempt: attempt }
      )
      return
    end
    return unless intervention.technician.consent_given? # safety net, see SPEC.md section 9
    return unless intervention.technician.region.present? && intervention.technician.locale.present?

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

    script = CallScripts.check_in(intervention)

    response = CallEClient.create_call(
      task: script[:task],
      recipient: intervention.technician.call_e_recipient,
      result_schema: script[:result_schema],
      metadata: { intervention_id: intervention.id, call_id: call.id, attempt: attempt },
      idempotency_key: "check_in_#{intervention.id}_attempt_#{attempt}"
    )

    call.update!(call_e_call_id: response["call_id"], call_status: "in_progress")
  rescue CallEClient::RateLimitError => e
    Rails.logger.warn("CheckInCallJob rate-limited for intervention=#{intervention.id}, retrying in 2min: #{e.message}")
    call.destroy # this attempt never actually reached CALL-E, don't leave a phantom Call record
    self.class.set(wait: 2.minutes).perform_later(intervention, attempt: attempt)
  rescue CallEClient::CallEError => e
    Rails.logger.error("CheckInCallJob failed for intervention=#{intervention.id}: #{e.message}")
    AuditLog.create!(
      intervention: intervention, actor: "system", event_type: "call_error",
      details: { call_type: "check_in", error: e.message }
    )
  end
end
