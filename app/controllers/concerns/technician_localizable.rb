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

  # Every language CALL-E supports across its recipient regions (see
  # CallESupportedRegions) — shown in the UI language switcher in each
  # language's own name, the standard convention for language pickers.
  # UI translations exist for all of these; any technician.locale we
  # don't have a translation for yet (there are none left, but this is
  # the extension point) falls back to English rather than raising.
  LOCALE_NAMES = {
    en: "English",
    fr: "Français",
    hi: "हिन्दी",
    ar: "العربية",
    vi: "Tiếng Việt",
    de: "Deutsch",
    ja: "日本語",
    es: "Español",
    pt: "Português"
  }.freeze

  RTL_LOCALES = %i[ar].freeze

  included do
    around_action :use_technician_locale
    helper_method :current_technician_locale, :technician_locale_options, :technician_text_direction
  end

  private

  def technician_locale_options
    I18n.available_locales.map { |code| [LOCALE_NAMES.fetch(code, code.to_s), code] }
  end

  def technician_text_direction(locale = current_technician_locale)
    RTL_LOCALES.include?(locale) ? "rtl" : "ltr"
  end

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
