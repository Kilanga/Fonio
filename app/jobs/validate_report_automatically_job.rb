# Auto-validates a closing report if the technician hasn't reviewed/edited it
# within the 2h window (see SPEC.md section 7).
class ValidateReportAutomaticallyJob < ApplicationJob
  queue_as :default

  def perform(call)
    return unless call.report_draft?

    call.update!(report_status: "validated")
    intervention = call.intervention
    new_status = call.is_anomaly_severe? ? "action_required" : "completed"
    intervention.update!(status: new_status, completed_at: (new_status == "completed" ? Time.current : nil))

    AuditLog.create!(
      intervention: intervention, technician: intervention.technician,
      actor: "system", event_type: "report_auto_validated",
      details: { call_id: call.id, resulting_status: new_status }
    )

    broadcast_update(intervention)
  end

  private

  def broadcast_update(intervention)
    Turbo::StreamsChannel.broadcast_replace_to(
      "interventions",
      target: "intervention_#{intervention.id}",
      partial: "interventions/card",
      locals: { intervention: intervention }
    )
  end
end
