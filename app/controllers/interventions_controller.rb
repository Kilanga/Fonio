require "csv"

class InterventionsController < ApplicationController
  include PmAuthenticatable
  include BroadcastsAvailablePool

  def pending
    @interventions = Intervention.pending.includes(:technician).order(:scheduled_at)
  end

  def in_progress
    @interventions = Intervention.in_progress.or(Intervention.closing_in_progress)
                                  .includes(:technician, :calls).order(:started_at)
  end

  def tracking
    @interventions = Intervention.where.not(status: [:pending, :in_progress])
                                  .includes(:technician, calls: { photos_attachments: :blob })

    if params[:status].present? && Intervention.statuses.key?(params[:status])
      @interventions = @interventions.where(status: params[:status])
    end
    @interventions = @interventions.joins(:technician).where(technicians: { name: params[:technician] }) if params[:technician].present?
    @interventions = @interventions.where(site_name: params[:site]) if params[:site].present?
    if params[:q].present?
      q = "%#{params[:q]}%"
      @interventions = @interventions.joins(:technician).where(
        "interventions.site_name ILIKE :q OR technicians.name ILIKE :q", q: q
      )
    end

    @interventions = @interventions.order(started_at: :desc)
  end

  def index
    redirect_to pending_interventions_path
  end

  def new
    @intervention = Intervention.new
    @technicians = Technician.where(consent_given: true).order(:name)
  end

  def create
    @intervention = Intervention.new(intervention_params)
    if @intervention.save
      AuditLog.create!(
        intervention: @intervention, technician: @intervention.technician,
        actor: "pm", event_type: "intervention_created"
      )
      broadcast_available_pool if @intervention.technician_id.nil?
      redirect_to pending_interventions_path, notice: "Intervention scheduled."
    else
      @technicians = Technician.where(consent_given: true).order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @intervention = Intervention.includes(:technician, calls: { photos_attachments: :blob }).find(params[:id])
    @audit_logs = @intervention.audit_logs.recent_first
  end

  def cancel
    @intervention = Intervention.find(params[:id])
    @intervention.cancel!
    redirect_to pending_interventions_path, notice: "Intervention cancelled — no call will be placed."
  end

  def resolve
    @intervention = Intervention.find(params[:id])
    @intervention.update!(status: "completed", completed_at: Time.current)
    AuditLog.create!(
      intervention: @intervention, technician: @intervention.technician,
      actor: "pm", event_type: "manually_resolved"
    )
    redirect_to tracking_interventions_path, notice: "Marked as resolved."
  end

  # Bypasses the T+30min wait — mainly so judges/demo viewers don't have to
  # sit around for the scheduled check-in call to see CALL-E in action.
  # CheckInCallJob itself guards against the originally-scheduled call
  # firing a second time afterward.
  def trigger_check_in
    @intervention = Intervention.find(params[:id])
    if @intervention.trigger_check_in_call!(actor: "pm")
      redirect_to intervention_path(@intervention), notice: "Check-in call triggered."
    else
      redirect_to intervention_path(@intervention), alert: "This intervention isn't in progress."
    end
  end

  def export
    interventions = Intervention.includes(:technician, :calls).order(started_at: :desc)

    csv = CSV.generate(headers: true) do |rows|
      rows << [
        "Site", "Technician", "Status", "Scheduled at", "Started at", "Completed at",
        "Resolution time (min)", "Work completed", "Equipment used", "Anomalies",
        "Anomaly severe", "Recommendations"
      ]
      interventions.each do |i|
        report = i.calls.find { |c| c.call_type == "closing_report" }
        rows << [
          i.site_name, i.technician&.name || "Unassigned", i.status, i.scheduled_at, i.started_at, i.completed_at,
          i.resolution_time_minutes, report&.work_completed, report&.equipment_used,
          report&.anomalies, report&.is_anomaly_severe, report&.recommendations
        ]
      end
    end

    send_data csv, filename: "interventions-#{Date.current.iso8601}.csv"
  end

  private

  def intervention_params
    params.require(:intervention).permit(:technician_id, :site_name, :site_address, :scheduled_at, :expected_end_time)
  end
end
