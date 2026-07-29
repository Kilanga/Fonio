module TechnicianPortal
  class InterventionsController < BaseController
    before_action :require_confirmed_session
    before_action :find_intervention, only: [:show, :accept, :start_intervention]

    def index
      @pending = current_technician.interventions.pending.order(:scheduled_at)
      @in_progress = current_technician.interventions.in_progress.or(
        current_technician.interventions.closing_in_progress
      )
    end

    def show
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

    private

    def find_intervention
      @intervention = current_technician.interventions.find(params[:id])
    end
  end
end
