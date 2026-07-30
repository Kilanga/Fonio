module TechnicianPortal
  class InterventionsController < BaseController
    before_action :require_confirmed_session
    before_action :find_intervention, only: [:show, :accept, :start_intervention, :finish]

    def index
      @pending = current_technician.interventions.pending.order(:scheduled_at)
      @in_progress = current_technician.interventions.in_progress.or(
        current_technician.interventions.closing_in_progress
      )
    end

    def show
      @check_in_call = @intervention.calls.type_check_in.order(created_at: :desc).first
      @closing_report_call = @intervention.calls.type_closing_report
        .report_draft.order(created_at: :desc).first
      @pm_messages = @intervention.audit_logs
        .where(event_type: "instruction_sent_to_technician").order(created_at: :desc)
    end

    def accept
      @intervention.update!(accepted_at: Time.current)
      AuditLog.create!(
        intervention: @intervention, technician: current_technician,
        actor: "technician", event_type: "intervention_accepted"
      )
      redirect_to technician_intervention_path(@intervention), notice: t("technician.interventions.accepted_flash")
    end

    def start_intervention
      unless @intervention.accepted_at?
        redirect_to technician_intervention_path(@intervention), alert: t("technician.interventions.accept_first")
        return
      end
      @intervention.start!
      redirect_to technician_interventions_path, notice: t("technician.interventions.started_flash")
    end

    # Replaces the old "text DONE" SMS signal — the technician taps this
    # button in the portal instead. Same effect: kicks off the closing
    # report call.
    def finish
      unless @intervention.in_progress?
        redirect_to technician_intervention_path(@intervention), alert: t("technician.interventions.finish_not_ready")
        return
      end
      @intervention.update!(status: "closing_in_progress")
      AuditLog.create!(
        intervention: @intervention, technician: current_technician,
        actor: "technician", event_type: "marked_done"
      )
      ClosingReportCallJob.perform_later(@intervention)
      Turbo::StreamsChannel.broadcast_replace_to(
        "interventions",
        target: "intervention_#{@intervention.id}",
        partial: "interventions/card",
        locals: { intervention: @intervention }
      )
      redirect_to technician_intervention_path(@intervention), notice: t("technician.interventions.finish_flash")
    end

    private

    def find_intervention
      @intervention = current_technician.interventions.find(params[:id])
    end
  end
end
