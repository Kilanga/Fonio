# Public, no-login, tokenized report-editing page for technicians
# (Kizeo-style edit of the CALL-E-transcribed closing report). See SPEC.md
# section 7.
class ReportsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:update] # no CSRF session on a public SMS link
  before_action :find_call_by_token

  def edit
    render :edit
  end

  def update
    if @call.report_validated?
      redirect_to edit_report_path(token: @call.edit_token), alert: "This report has already been validated."
      return
    end

    if @call.update(report_params)
      @call.update!(report_status: "validated")
      intervention = @call.intervention
      new_status = @call.is_anomaly_severe? ? "action_required" : "completed"
      intervention.update!(status: new_status, completed_at: (new_status == "completed" ? Time.current : nil))

      AuditLog.create!(
        intervention: intervention, technician: intervention.technician,
        actor: "technician", event_type: "report_validated_by_technician"
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        "interventions", target: "intervention_#{intervention.id}",
        partial: "interventions/card", locals: { intervention: intervention }
      )

      render :confirmation
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def find_call_by_token
    @call = Call.find_by!(edit_token: params[:token])
    head(:gone) unless @call.edit_token_valid? || @call.report_draft?
  end

  def report_params
    params.require(:call).permit(
      :work_completed, :equipment_used, :anomalies, :recommendations,
      :actual_duration_minutes, :is_anomaly_severe, photos: []
    )
  end
end
