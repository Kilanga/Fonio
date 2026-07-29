require "openssl"
require "base64"

module Webhooks
  # Receives structured results from CALL-E for all three call types
  # (check_in, closing_report, daily_summary), distinguished by the
  # metadata echoed back in the payload. See SPEC.md section 8.
  #
  # NOTE: exact payload shape (field names, nesting) should be verified
  # against CALL-E's actual webhook contract once tested live — this
  # reflects our best assumption at build time.
  class CallEController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :verify_calle_signature!

    def create
      payload = params.to_unsafe_h
      call_id = payload.dig("metadata", "call_id")

      if call_id.present?
        handle_technician_call(payload, call_id)
      elsif payload.dig("metadata", "daily_summary_call_id").present?
        handle_daily_summary(payload)
      end

      head :ok
    rescue ActiveRecord::RecordNotFound => e
      # Unknown call_id — either a stale/replayed webhook or a spoofed one.
      # Don't 500 (CALL-E would just retry forever); log and drop it.
      Rails.logger.error("[webhooks/call_e] unknown record: #{e.message}")
      head :ok
    rescue StandardError => e
      # CALL-E's contract is still a beta assumption (see note above) — a
      # payload shape we didn't anticipate should never take the whole
      # request down. Log loudly so it's caught in review, but still ack
      # the webhook so the provider doesn't retry-storm us.
      Rails.logger.error("[webhooks/call_e] unhandled error: #{e.class}: #{e.message}\n#{payload.inspect}")
      head :ok
    end

    private

    # Best-effort HMAC verification. CALL-E's exact webhook-signing scheme
    # isn't confirmed in their public docs as of this beta — this assumes a
    # shared-secret HMAC-SHA256 over the raw body in an `X-CallE-Signature`
    # header, which is the common convention (Stripe/GitHub-style). Verify
    # against docs.heycall-e.com and adjust the header name / algorithm if
    # needed once confirmed.
    #
    # If CALLE_WEBHOOK_SECRET isn't configured, this logs a warning and lets
    # the request through rather than break the demo — set it as soon as
    # CALL-E issues one, at which point verification becomes mandatory.
    def verify_calle_signature!
      return if skip_webhook_signature_check?

      secret = ENV["CALLE_WEBHOOK_SECRET"]
      if secret.blank?
        Rails.logger.warn("[SECURITY] CALLE_WEBHOOK_SECRET not set — accepting call_e webhook without signature verification")
        return
      end

      signature = request.headers["X-CallE-Signature"]
      if signature.blank?
        Rails.logger.warn("[SECURITY] Rejected call_e webhook: missing X-CallE-Signature header")
        return head(:unauthorized)
      end

      body = request.raw_post
      expected_signature = OpenSSL::HMAC.hexdigest("sha256", secret, body)

      unless ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature)
        Rails.logger.warn("[SECURITY] Rejected call_e webhook: invalid signature")
        return head(:unauthorized)
      end
    end

    def handle_technician_call(payload, call_id)
      call = Call.find(call_id)
      call.update!(
        call_status: normalized_call_status(payload["status"]),
        raw_payload: payload
      )

      AuditLog.create!(
        intervention: call.intervention, technician: call.intervention.technician,
        actor: "call_e", event_type: "call_result_received",
        details: { call_type: call.call_type, call_status: call.call_status }
      )

      if call.status_no_answer? || call.status_voicemail?
        handle_no_answer(call)
      elsif call.type_check_in?
        apply_check_in_result(call, payload["structured_result"] || {})
      elsif call.type_closing_report?
        apply_closing_report_result(call, payload["structured_result"] || {})
      end

      broadcast_update(call.intervention)
    end

    # CALL-E's beta contract may send call_status values we haven't seen
    # yet — an unrecognized enum value would otherwise raise and crash the
    # webhook. Fall back to leaving the status untouched (nil on a fresh
    # call, unchanged on an update) and log it for follow-up instead.
    def normalized_call_status(status)
      return status if Call.call_statuses.key?(status)

      Rails.logger.warn("[webhooks/call_e] unrecognized call_status=#{status.inspect} — ignoring")
      nil
    end

    def handle_no_answer(call)
      intervention = call.intervention
      return unless call.type_check_in?

      if call.attempt == 1
        CheckInCallJob.set(wait: 5.minutes).perform_later(intervention, attempt: 2)
      else
        intervention.update!(status: "call_failed")
        AuditLog.create!(
          intervention: intervention, technician: intervention.technician,
          actor: "system", event_type: "status_changed",
          details: { new_status: "call_failed" }
        )
      end
    end

    def apply_check_in_result(call, result)
      intervention = call.intervention

      call.update!(
        has_started: result["has_started"],
        has_issue: result["has_issue"],
        severity: result["severity"],
        issue_type: result["issue_type"],
        needs_help: result["needs_help"],
        help_needed_description: result["help_needed_description"],
        revised_eta: result["revised_eta"]
      )

      new_status =
        if result["has_started"] == false
          "no_show"
        elsif result["has_issue"] || result["needs_help"]
          "action_required"
        else
          "in_progress"
        end

      intervention.update!(status: new_status)
      AuditLog.create!(
        intervention: intervention, technician: intervention.technician,
        actor: "system", event_type: "status_changed", details: { new_status: new_status }
      )

      # There's no review/edit step on check-in results the way there is
      # for closing reports (SPEC.md section 7) — a misheard "blocking"
      # vs "minor" would otherwise go straight to the PM unchecked. A
      # confirmation text is a much lighter safety net than a full web
      # form, and only fires when something was actually flagged so a
      # routine "all good" check-in doesn't get an SMS.
      send_check_in_confirmation(call, intervention) if call.has_issue? || call.needs_help?
    end

    def send_check_in_confirmation(call, intervention)
      summary = [
        call.issue_type.present? ? "issue: #{call.issue_type.humanize.downcase}" : nil,
        call.severity.present? ? "severity: #{call.severity}" : nil,
        call.needs_help? ? "help requested" : nil
      ].compact.join(", ")

      SmsClient.send_sms(
        to: intervention.technician.phone,
        body: "Fonio noted from your check-in call: #{summary}. " \
              "If that's wrong, please call your PM directly to correct it."
      )
    rescue SmsClient::SmsError => e
      Rails.logger.error("Failed to send check-in confirmation for call=#{call.id}: #{e.message}")
      AuditLog.create!(
        intervention: intervention, actor: "system", event_type: "sms_error",
        details: { context: "check_in_confirmation", error: e.message }
      )
    end

    def apply_closing_report_result(call, result)
      call.update!(
        work_completed: result["work_completed"],
        equipment_used: result["equipment_used"],
        anomalies: result["anomalies"],
        recommendations: result["recommendations"],
        actual_duration_minutes: result["actual_duration_minutes"],
        is_anomaly_severe: result["is_anomaly_severe"],
        report_status: "draft"
      )

      ValidateReportAutomaticallyJob.set(wait: 2.hours).perform_later(call)

      # Send the technician their edit link right away
      begin
        SmsClient.send_sms(
          to: call.intervention.technician.phone,
          body: "Here's your closing report to review or edit: " \
                "#{Rails.application.routes.url_helpers.edit_report_url(token: call.edit_token, host: default_host)}"
        )
      rescue SmsClient::SmsError => e
        Rails.logger.error("Failed to send report edit link for call=#{call.id}: #{e.message}")
        AuditLog.create!(
          intervention: call.intervention, actor: "system", event_type: "sms_error",
          details: { context: "report_edit_link", error: e.message }
        )
      end
    end

    def handle_daily_summary(payload)
      summary = DailySummaryCall.find(payload.dig("metadata", "daily_summary_call_id"))
      summary.update!(
        call_status: normalized_call_status(payload["status"]),
        raw_payload: payload
      )
    end

    def broadcast_update(intervention)
      Turbo::StreamsChannel.broadcast_replace_to(
        "interventions",
        target: "intervention_#{intervention.id}",
        partial: "interventions/card",
        locals: { intervention: intervention }
      )
    end

    def default_host
      ENV.fetch("APP_HOST", "localhost:3000")
    end
  end
end
