module TechnicianPortal
  # Requests a one-time SMS login code — the fallback path alongside
  # password login (see SPEC.md 3bis / earlier decision to support both).
  class LoginCodesController < ApplicationController
    layout "technician"
    def create
      technician = ::Technician.find_by(phone: params[:phone])

      if technician&.activated?
        code = technician.generate_login_code!
        begin
          SmsClient.send_sms(to: technician.phone, body: "Your Fonio login code: #{code} (valid 10 minutes)")
        rescue SmsClient::SmsError => e
          Rails.logger.error("Failed to send login code to technician=#{technician.id}: #{e.message}")
        end
      end

      # Same response whether or not the phone matches an activated
      # technician, to avoid leaking which numbers are registered.
      redirect_to technician_login_path, notice: "If that number is registered, a code has been texted to it."
    end
  end
end
