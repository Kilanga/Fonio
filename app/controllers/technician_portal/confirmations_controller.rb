module TechnicianPortal
  # Every login requires the technician to explicitly confirm (or change)
  # their phone number and preferred region/language before proceeding —
  # never inferred automatically. See SPEC.md section 3bis and the
  # community safety rule this satisfies.
  class ConfirmationsController < BaseController
    def new
    end

    def create
      if current_technician.update(confirmation_params)
        session[:technician_confirmed] = true
        AuditLog.create!(
          technician: current_technician, actor: "technician", event_type: "details_confirmed_at_login",
          details: { region: current_technician.region, locale: current_technician.locale }
        )
        redirect_to technician_interventions_path, notice: "Thanks, you're all set."
      else
        flash.now[:alert] = current_technician.errors.full_messages.join(", ")
        render :new, status: :unprocessable_entity
      end
    end

    private

    def confirmation_params
      params.require(:technician).permit(:phone, :region, :locale)
    end
  end
end
