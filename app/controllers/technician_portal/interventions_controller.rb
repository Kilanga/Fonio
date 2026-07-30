module TechnicianPortal
  class InterventionsController < BaseController
    before_action :require_confirmed_session
    before_action :find_intervention, only: [:show, :accept, :start_intervention, :finish]
    before_action :find_open_intervention, only: [:claim]

    def index
      @pending = current_technician.interventions.pending.order(:scheduled_at)
      @in_progress = current_technician.interventions.in_progress.or(
        current_technician.interventions.closing_in_progress
      )
      # Shared pool: interventions nobody has claimed yet, and a read-only
      # view of what other technicians are currently handling — so a
      # technician can see the full picture, not just their own slice.
      @available = Intervention.available_to_claim.order(:scheduled_at)
      @others = Intervention.where.not(technician_id: [nil, current_technician.id])
        .where(status: %w[pending in_progress closing_in_progress])
        .includes(:technician).order(:scheduled_at)
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

    # Self-service pickup from the shared pool (see Intervention#claim!).
    def claim
      if @intervention.claim!(current_technician)
        redirect_to technician_intervention_path(@intervention), notice: t("technician.interventions.claimed_flash")
      else
        redirect_to technician_interventions_path, alert: t("technician.interventions.already_claimed_alert")
      end
    end

    private

    def find_intervention
      @intervention = current_technician.interventions.find(params[:id])
    end

    # Not scoped to current_technician — claiming is how it *becomes*
    # theirs. Intervention#claim! re-checks technician_id.nil? under a row
    # lock, so this is safe even if the pool listing is briefly stale.
    def find_open_intervention
      @intervention = Intervention.find(params[:id])
    end
  end
end
