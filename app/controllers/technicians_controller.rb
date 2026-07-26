class TechniciansController < ApplicationController
  def index
    @technicians = Technician.order(:name)
  end

  def new
    @technician = Technician.new
  end

  def create
    @technician = Technician.new(technician_params)
    if @technician.save
      redirect_to technicians_path, notice: "Technician added. Consent must still be confirmed before calling them."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PM explicitly confirms the technician has been informed and consents to
  # receiving AI-initiated phone calls and texts (SPEC.md section 9/11).
  def consent
    @technician = Technician.find(params[:id])
    @technician.give_consent!
    redirect_to technicians_path, notice: "Consent recorded for #{@technician.name}."
  end

  private

  def technician_params
    params.require(:technician).permit(:name, :phone)
  end
end
