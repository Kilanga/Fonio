# The fixed list of recipient regions and languages CALL-E supports (Phase 1
# beta), per https://github.com/CALLE-AI/call-e-integrations. The conversation
# language is tied to the recipient's region code — there is no free-form
# "detect any language" mode.
#
# NOTE on region vs. locale: the docs only show a table of
# "recipient region code -> language(s)" without explicitly stating whether
# `region` is the phone number's dialing/country code (used for call
# routing) or purely a language selector unrelated to the number itself.
# The most plausible reading — and the one this app assumes — is that
# `region` corresponds to the technician's phone country code (needed for
# routing the call correctly), while `locale` separately picks the specific
# spoken language among what that region offers. This should be confirmed
# against a real account/support before relying on it in production.
module CallESupportedRegions
  REGIONS = {
    "US" => { languages: ["en"], locales: ["en-US"] },
    "SG" => { languages: ["en"], locales: ["en-SG"] },
    "MY" => { languages: ["en"], locales: ["en-MY"] },
    "IN" => { languages: ["en", "hi"], locales: ["en-IN", "hi-IN"] },
    "AE" => { languages: ["en", "ar"], locales: ["en-AE", "ar-AE"] },
    "AU" => { languages: ["en"], locales: ["en-AU"] },
    "CA" => { languages: ["en"], locales: ["en-CA"] },
    "GB" => { languages: ["en"], locales: ["en-GB"] },
    "VN" => { languages: ["vi"], locales: ["vi-VN"] },
    "DE" => { languages: ["en", "de"], locales: ["en-DE", "de-DE"] },
    "JP" => { languages: ["ja"], locales: ["ja-JP"] },
    "FR" => { languages: ["fr"], locales: ["fr-FR"] },
    "MX" => { languages: ["es"], locales: ["es-MX"] },
    "BR" => { languages: ["pt"], locales: ["pt-BR"] },
    "ID" => { languages: ["en"], locales: ["en-ID"] },
    "PH" => { languages: ["en"], locales: ["en-PH"] },
    "KE" => { languages: ["en"], locales: ["en-KE"] }
  }.freeze

  # E.164 country calling codes mapped to CALL-E region codes, for
  # auto-suggesting a technician's region from their phone number. Only
  # codes with a supported CALL-E region are listed. Some calling codes
  # (e.g. +1) are shared by multiple countries (US/CA) and can't be
  # disambiguated automatically — the PM can still override the suggestion.
  CALLING_CODE_TO_REGION = {
    "1" => "US",     # also covers CA; ambiguous, defaults to US
    "65" => "SG",
    "60" => "MY",
    "91" => "IN",
    "971" => "AE",
    "61" => "AU",
    "44" => "GB",
    "84" => "VN",
    "49" => "DE",
    "81" => "JP",
    "33" => "FR",
    "52" => "MX",
    "55" => "BR",
    "62" => "ID",
    "63" => "PH",
    "254" => "KE"
  }.freeze

  def self.region_codes
    REGIONS.keys
  end

  def self.locales_for(region)
    REGIONS.dig(region, :locales) || []
  end

  def self.valid?(region, locale)
    locales_for(region).include?(locale)
  end

  # Best-effort guess only — always let the PM confirm/override in the UI.
  def self.guess_region_from_phone(phone)
    digits = phone.to_s.delete("^0-9")
    # Try longest calling codes first (e.g. "971" before "1")
    CALLING_CODE_TO_REGION.keys.sort_by { |c| -c.length }.find { |code| digits.start_with?(code) }
      &.then { |code| CALLING_CODE_TO_REGION[code] }
  end
end
