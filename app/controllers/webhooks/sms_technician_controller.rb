require "openssl"
require "base64"

module Webhooks
  # Receives the technician's "DONE" SMS (Twilio inbound webhook), which
  # closes out an intervention and triggers the closing report call.
  # See SPEC.md sections 5, 8, 10 (duplicate detection).
  class SmsTechnicianController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :verify_twilio_signature!

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

    private

    # Verifies the X-Twilio-Signature header per Twilio's documented
    # algorithm (HMAC-SHA1 of the full request URL + sorted POST params,
    # keyed with the account auth token), so this endpoint can't be spoofed
    # by anyone who guesses/knows a technician's phone number.
    # https://www.twilio.com/docs/usage/webhooks/webhooks-security
    def verify_twilio_signature!
      return if skip_webhook_signature_check?

      auth_token = ENV["TWILIO_AUTH_TOKEN"]
      if auth_token.blank?
        Rails.logger.error("[SECURITY] TWILIO_AUTH_TOKEN not set — rejecting inbound SMS webhook, cannot verify signature")
        return head(:unauthorized)
      end

      signature = request.headers["X-Twilio-Signature"]
      return head(:unauthorized) if signature.blank?

      data = request.original_url.dup
      request.request_parameters.sort.each { |key, value| data << key << value.to_s }

      expected_signature = Base64.strict_encode64(OpenSSL::HMAC.digest("sha1", auth_token, data))

      unless ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature)
        Rails.logger.warn("[SECURITY] Rejected inbound SMS webhook: invalid Twilio signature")
        return head(:unauthorized)
      end
    end
  end
end
