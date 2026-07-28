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
      begin
        SmsClient.send_sms(
          to: @technician.phone,
          body: "Hi #{@technician.name}, set up your Fonio account here: " \
                "#{Rails.application.routes.url_helpers.technician_activation_url(token: @technician.activation_token, host: default_host)}"
        )
        redirect_to technicians_path, notice: "Technician added. An activation link has been texted to them."
      rescue SmsClient::SmsError => e
        Rails.logger.error("Failed to send activation SMS to technician=#{@technician.id}: #{e.message}")
        activation_url = Rails.application.routes.url_helpers.technician_activation_url(token: @technician.activation_token, host: default_host)
        redirect_to technicians_path,
          alert: "Technician added, but the activation text failed to send. Share this link with them directly: #{activation_url}"
      end
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
end
