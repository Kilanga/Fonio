module Webhooks
  # Receives the technician's "DONE" SMS (Twilio inbound webhook), which
  # closes out an intervention and triggers the closing report call.
  # See SPEC.md sections 5, 8, 10 (duplicate detection).
  class SmsTechnicianController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      from = params[:From]
      body = params[:Body].to_s.strip.downcase

      technician = Technician.find_by(phone: from)

      unless technician
        AuditLog.create!(actor: "system", event_type: "sms_unknown_number", details: { from: from, body: body })
        return head(:ok)
      end

      unless body == "done"
        AuditLog.create!(technician: technician, actor: "system", event_type: "sms_ignored_unrecognized", details: { body: body })
        return head(:ok)
      end

      intervention = technician.active_intervention # scope: in_progress only

      unless intervention
        # Either no active intervention, or this is a duplicate "DONE" sent
        # after the intervention has already moved past in_progress.
        AuditLog.create!(technician: technician, actor: "system", event_type: "sms_ignored_duplicate", details: { body: body })
        return head(:ok)
      end

      intervention.update!(status: "closing_in_progress")
      AuditLog.create!(
        intervention: intervention, technician: technician,
        actor: "technician", event_type: "sms_done_received"
      )
      ClosingReportCallJob.perform_later(intervention)

      Turbo::StreamsChannel.broadcast_replace_to(
        "interventions",
        target: "intervention_#{intervention.id}",
        partial: "interventions/card",
        locals: { intervention: intervention }
      )

      head :ok
    end
  end
end
