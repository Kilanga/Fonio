module TechnicianPortal
  class ActivationsController < ApplicationController
    layout "technician"
    before_action :find_technician_by_token

    def new
      redirect_to technician_login_path, alert: "This activation link is invalid or has expired." unless @technician
    end

    def create
      unless @technician
        redirect_to technician_login_path, alert: "This activation link is invalid or has expired."
        return
      end

      if @technician.activate!(password: params[:password], password_confirmation: params[:password_confirmation])
        session[:technician_id] = @technician.id
        session[:technician_confirmed] = nil
        redirect_to technician_confirm_path, notice: "Account activated — please confirm your details to continue."
      else
        flash.now[:alert] = @technician.errors.full_messages.join(", ").presence || "Could not activate account."
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
