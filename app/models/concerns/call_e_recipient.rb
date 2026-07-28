# Shared behavior for any model that can be a CALL-E call recipient
# (Technician, Pm): region/locale validation against the supported list,
# and the `recipient` hash shape CALL-E's API expects. See
# app/models/concerns/call_e_supported_regions.rb for the region/locale data.
module CallERecipient
  extend ActiveSupport::Concern

  included do
    validates :region, inclusion: { in: CallESupportedRegions.region_codes }, allow_nil: true
    validate :locale_matches_region
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
