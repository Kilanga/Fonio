class Technician < ApplicationRecord
  has_many :interventions, dependent: :restrict_with_error
  has_many :audit_logs, dependent: :nullify

  validates :name, presence: true
  validates :phone, presence: true, uniqueness: true
  validates :region, presence: true, inclusion: { in: CallESupportedRegions.region_codes }
  validates :locale, presence: true
  validate :locale_matches_region

  def give_consent!
    update!(consent_given: true, consent_given_at: Time.current)
    AuditLog.create!(technician: self, actor: "pm", event_type: "consent_given", details: { phone: phone })
  end

  def active_intervention
    interventions.in_progress.order(started_at: :desc).first
  end

  # Shape expected by CALL-E's "recipient" object in POST /v1/calls
  def call_e_recipient
    { phone: phone, region: region, locale: locale }
  end

  private

  def locale_matches_region
    return if region.blank? || locale.blank?
    unless CallESupportedRegions.valid?(region, locale)
      errors.add(:locale, "must be one of #{CallESupportedRegions.locales_for(region).join(', ')} for region #{region}")
    end
  end
end
