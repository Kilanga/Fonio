# Renders the technician-facing account area in the technician's own
# preferred language, instead of always English — the AI phone call
# already adapts to `technician.locale` (see CallScripts /
# CallESupportedRegions), but until now the web UI never did, which meant
# a non-English-speaking technician got a call in their language and then
# an unreadable confirmation/activation page. See SPEC.md 3bis.
#
# The locale is stashed in the session (set on login/confirm, see
# TechnicianPortal::SessionsController and ConfirmationsController)
# rather than read fresh from the DB on every request, so it survives the
# brand-new-technician case where `technician.locale` isn't set yet
# (nothing to localize with until their first confirm step).
module TechnicianLocalizable
  extend ActiveSupport::Concern

  included do
    around_action :use_technician_locale
    helper_method :current_technician_locale
  end

  private

  def use_technician_locale(&block)
    I18n.with_locale(current_technician_locale, &block)
  end

  def current_technician_locale
    normalize_locale(session[:technician_locale]) || I18n.default_locale
  end

  # Technician locale is stored as a CALL-E-style IETF tag like "fr-FR"
  # (see CallESupportedRegions) — map to the closest available I18n
  # locale, falling back to the app default if we don't have that
  # translation yet rather than raising.
  def normalize_locale(raw)
    return nil if raw.blank?

    lang = raw.to_s.split("-").first&.downcase&.to_sym
    lang if I18n.available_locales.include?(lang)
  end
end
