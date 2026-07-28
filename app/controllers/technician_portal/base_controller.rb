module TechnicianPortal
  # Shared auth for the technician-facing account area. Session-based,
  # entirely separate from the PM interface (which has no auth in this
  # MVP — see SPEC.md section 3 for that assumption).
  class BaseController < ApplicationController
    layout "technician"
    before_action :require_technician_login

    private

    def current_technician
      @current_technician ||= ::Technician.find_by(id: session[:technician_id])
    end
    helper_method :current_technician

    def require_technician_login
      redirect_to technician_login_path, alert: "Please log in." unless current_technician
    end

    # Every login requires a fresh confirm-phone-and-language step (see
    # SPEC.md 3bis) before the technician can view or act on interventions.
    # The flag is session-scoped, so it's naturally reset on each new login.
    def require_confirmed_session
      return if session[:technician_confirmed]
      redirect_to technician_confirm_path, alert: "Please confirm your details first."
    end
  end
end
