# Basic-auth gate for the PM-facing interface (interventions, technicians,
# dashboard, audit logs, profile). This is a single-PM MVP with no user
# accounts, so HTTP Basic is the fastest way to stop the app from being
# wide open to anyone with the URL — see SPEC.md section 3.
#
# NOT included on: ReportsController (public tokenized link for
# technicians), Webhooks::* (called by CALL-E/Twilio, verified by
# signature instead), TechnicianPortal::* (has its own session auth).
#
# Set PM_AUTH_USER / PM_AUTH_PASSWORD in .env. Falls back to a default
# dev-only credential so the app still boots without configuration, but
# logs a loud warning so it's never silently left insecure.
module PmAuthenticatable
  extend ActiveSupport::Concern

  DEFAULT_PASSWORD = "changeme".freeze

  included do
    http_basic_authenticate_with(
      name: ENV.fetch("PM_AUTH_USER", "pm"),
      password: ENV.fetch("PM_AUTH_PASSWORD", DEFAULT_PASSWORD),
      realm: "Fonio"
    )

    before_action :warn_if_default_pm_password
  end

  private

  def warn_if_default_pm_password
    return if ENV["PM_AUTH_PASSWORD"].present? && ENV["PM_AUTH_PASSWORD"] != DEFAULT_PASSWORD

    Rails.logger.warn(
      "[SECURITY] PM_AUTH_PASSWORD is not set (or set to the default) — " \
      "the PM interface is protected by a well-known password. Set PM_AUTH_USER " \
      "and PM_AUTH_PASSWORD in .env before sharing this app's URL with anyone."
    )
  end
end
