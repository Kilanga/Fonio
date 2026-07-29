module TechnicianPortal
  class ActivationsController < ApplicationController
    include TechnicianLocalizable

    layout "technician"
    before_action :find_technician_by_token

    def new
      redirect_to technician_login_path, alert: t("technician.activation.invalid_link") unless @technician
    end

    def create
      unless @technician
        redirect_to technician_login_path, alert: t("technician.activation.invalid_link")
        return
      end

      if @technician.activate!(password: params[:password], password_confirmation: params[:password_confirmation])
        session[:technician_id] = @technician.id
        session[:technician_confirmed] = nil
        redirect_to technician_confirm_path, notice: t("technician.activation.success")
      else
        flash.now[:alert] = @technician.errors.full_messages.join(", ").presence || t("technician.activation.failed")
        render :new, status: :unprocessable_entity
      end
    end

    private

    def find_technician_by_token
      @technician = ::Technician.find_by(activation_token: params[:token])
      @technician = nil if @technician && !@technician.activation_token_valid?
    end
  end
end
