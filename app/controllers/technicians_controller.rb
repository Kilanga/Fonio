class TechniciansController < ApplicationController
  include PmAuthenticatable

  def index
    @technicians = Technician.order(:name)
  end

  def new
    @technician = Technician.new
  end

  def create
    @technician = Technician.new(technician_params)
    if @technician.save
      @technician.start_activation!
      redirect_to technicians_path,
        notice: "Technician added. Share their activation link with them (shown below) — " \
                "any way you like: WhatsApp, email, in person. Setting a password from that " \
                "link is their consent to receive AI-initiated calls."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def technician_params
    params.require(:technician).permit(:name, :phone)
  end

  def default_host
    ENV.fetch("APP_HOST", "localhost:3000")
  end
  helper_method :default_host
end
