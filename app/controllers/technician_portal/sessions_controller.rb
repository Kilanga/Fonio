module TechnicianPortal
  class SessionsController < ApplicationController
    layout "technician"
    before_action :throttle_login!, only: :create

    def new
    end

    def create
      technician = ::Technician.find_by(phone: params[:phone])

      if technician&.activated? && authenticated?(technician)
        technician.consume_login_code! if params[:code].present?
        log_in(technician)
        redirect_to technician_confirm_path
      else
        flash.now[:alert] = "Incorrect phone, password, or code."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      session[:technician_id] = nil
      session[:technician_confirmed] = nil
      redirect_to technician_login_path, notice: "Logged out."
    end

    private

    def throttle_login!
      key = "throttle:technician_login:#{request.remote_ip}:#{params[:phone]}"
      return unless rate_limited?(key, limit: 5, period: 1.minute)

      flash.now[:alert] = "Too many attempts — please wait a minute and try again."
      render :new, status: :too_many_requests
    end

    def authenticated?(technician)
      if params[:code].present?
        technician.verify_login_code(params[:code])
      else
        technician.authenticate(params[:password])
      end
    end

    def log_in(technician)
      session[:technician_id] = technician.id
      session[:technician_confirmed] = nil # always re-confirm on a fresh login
    end
  end
end
