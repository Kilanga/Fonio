module TechnicianPortal
  # Manual UI language switcher — deliberately separate from
  # `technician.locale` (which drives the CALL-E phone call language, see
  # CallESupportedRegions). A technician might want to read the app in one
  # language and be called in another, so this only ever touches the
  # session-scoped display preference, never the Technician record.
  class UiLocalesController < ApplicationController
    include TechnicianLocalizable

    def update
      locale = params[:locale].to_s
      session[:technician_locale] = locale if I18n.available_locales.map(&:to_s).include?(locale)

      redirect_back fallback_location: technician_login_path
    end
  end
end
