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
      broadcast_technician_detail(call.intervention)
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

      # There's no SMS confirmation step here (there used to be, before we
      # dropped the Twilio dependency) — a misheard "blocking" vs "minor"
      # would otherwise go straight to the PM unchecked. Instead the
      # technician sees the flagged issue directly in their portal
      # (technician_portal/interventions#show reads has_issue?/needs_help?
      # off the latest check-in Call) the next time they open the app.
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

      # The technician sees the "review your report" link directly in their
      # portal (technician_portal/interventions#show) next time they open
      # the app — no SMS needed.
    end

    def handle_daily_summary(payload)
      summary = DailySummaryCall.find(payload.dig("metadata", "daily_summary_call_id"))
      summary.update!(
        call_status: normalized_call_status(payload["status"]),
        raw_payload: payload
      )

      apply_daily_summary_decisions(summary, payload["structured_result"] || {})
    end

    # Turns the PM's spoken decisions during the recap call into real
    # actions — otherwise this call is just a read-out the PM could get
    # from a push notification. Deliberately conservative: only acts when
    # a decision's site_name resolves to exactly one flagged intervention
    # from that call's window. Anything ambiguous, unmatched, or using an
    # action we don't recognize is logged rather than guessed at, since
    # this is applying an AI's interpretation of a live phone conversation
    # — see the note on CALL-E's contract at the top of this file.
    def apply_daily_summary_decisions(summary, result)
      decisions = result["decisions"]
      return unless decisions.is_a?(Array) && decisions.any?

      flagged = summary.flagged_interventions.to_a
      decisions.filter_map { |decision| apply_daily_summary_decision(summary, flagged, decision) }
      # No SMS confirmation back to the PM — they were just on the phone,
      # and the dashboard already reflects the changes live via Turbo Streams.
    end

    def apply_daily_summary_decision(summary, flagged, decision)
      site_name = decision["site_name"].to_s
      action = decision["action"]
      return if site_name.blank?

      matches = flagged.select { |i| i.site_name.to_s.casecmp?(site_name) }
      matches = flagged.select { |i| i.site_name.to_s.downcase.include?(site_name.downcase) } if matches.empty?

      if matches.size != 1
        AuditLog.create!(
          actor: "call_e", event_type: "daily_summary_decision_unmatched",
          details: { site_name: site_name, action: action, candidates: matches.size, daily_summary_call_id: summary.id }
        )
        return nil
      end

      intervention = matches.first

      case action
      when "mark_resolved"
        intervention.update!(status: "completed", completed_at: Time.current)
        AuditLog.create!(
          intervention: intervention, technician: intervention.technician,
          actor: "pm", event_type: "manually_resolved",
          details: { via: "daily_summary_call", daily_summary_call_id: summary.id }
        )
        broadcast_update(intervention)
        { intervention: intervention, action: action }
      when "text_technician"
        # No longer sent via SMS — logged here, and the technician sees it
        # as a "message from your PM" banner in their portal
        # (technician_portal/interventions#show reads this exact event type).
        instruction = decision["instruction"].to_s
        return nil if instruction.blank?

        AuditLog.create!(
          intervention: intervention, technician: intervention.technician,
          actor: "pm", event_type: "instruction_sent_to_technician",
          details: { instruction: instruction, via: "daily_summary_call", daily_summary_call_id: summary.id }
        )
        broadcast_technician_detail(intervention)
        { intervention: intervention, action: action, instruction: instruction }
      else
        nil # "no_action", or an action we don't recognize — nothing to do
      end
    end

    def broadcast_update(intervention)
      Turbo::StreamsChannel.broadcast_replace_to(
        "interventions",
        target: "intervention_#{intervention.id}",
        partial: "interventions/card",
        locals: { intervention: intervention }
      )
    end

    # Live-updates the technician's own intervention detail page (check-in
    # results, PM messages, report-ready link) so they don't have to
    # manually reload to see it.
    def broadcast_technician_detail(intervention)
      technician = intervention.technician
      return unless technician

      check_in_call = intervention.calls.type_check_in.order(created_at: :desc).first
      closing_report_call = intervention.calls.type_closing_report.report_draft.order(created_at: :desc).first
      pm_messages = intervention.audit_logs.where(event_type: "instruction_sent_to_technician").order(created_at: :desc)

      Turbo::StreamsChannel.broadcast_replace_to(
        [technician, "interventions"],
        target: "technician_intervention_detail_#{intervention.id}",
        partial: "technician_portal/interventions/detail",
        locals: {
          intervention: intervention, pm_messages: pm_messages,
          check_in_call: check_in_call, closing_report_call: closing_report_call
        }
      )
    end

    def default_host
      ENV.fetch("APP_HOST", "localhost:3000")
    end
  end
end
