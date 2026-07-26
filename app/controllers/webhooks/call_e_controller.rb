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

    def create
      payload = params.to_unsafe_h
      call_id = payload.dig("metadata", "call_id")

      if call_id.present?
        handle_technician_call(payload, call_id)
      elsif payload.dig("metadata", "daily_summary_call_id").present?
        handle_daily_summary(payload)
      end

      head :ok
    end

    private

    def handle_technician_call(payload, call_id)
      call = Call.find(call_id)
      call.update!(
        call_status: payload["status"],
        raw_payload: payload
      )

      AuditLog.create!(
        intervention: call.intervention, technician: call.intervention.technician,
        actor: "call_e", event_type: "call_result_received",
        details: { call_type: call.call_type, call_status: call.call_status }
      )

      if call.status_no_answer?
        handle_no_answer(call)
      elsif call.type_check_in?
        apply_check_in_result(call, payload["structured_result"] || {})
      elsif call.type_closing_report?
        apply_closing_report_result(call, payload["structured_result"] || {})
      end

      broadcast_update(call.intervention)
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
        needs_help: result["needs_help"],
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
      SmsClient.send_sms(
        to: call.intervention.technician.phone,
        body: "Here's your closing report to review or edit: " \
              "#{Rails.application.routes.url_helpers.edit_report_url(token: call.edit_token, host: default_host)}"
      )
    end

    def handle_daily_summary(payload)
      summary = DailySummaryCall.find(payload.dig("metadata", "daily_summary_call_id"))
      summary.update!(call_status: payload["status"], raw_payload: payload)
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
