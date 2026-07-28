import { Controller } from "@hotwired/stimulus"

// Filters the "spoken language" <select> to only the locales valid for the
// PM's explicitly chosen region. Does NOT auto-fill region from the phone
// number — per CALL-E's own community safety guidance ("Do not infer
// critical call details from phone number, locale, IP address, UTC offset,
// language, or country code"), region and locale must be explicit choices,
// not inferred from the number. See
// app/models/concerns/call_e_supported_regions.rb for the source of truth.
export default class extends Controller {
  static targets = ["region", "locale"]

  connect() {
    this.regionsData = JSON.parse(document.getElementById("call-e-regions-data").textContent)
    if (this.regionTarget.value) this.updateLocales()
  }

  updateLocales() {
    const region = this.regionTarget.value
    const locales = this.regionsData[region] || []
    this.localeTarget.innerHTML = ""

    const placeholder = document.createElement("option")
    placeholder.textContent = locales.length ? "Select a language" : "Select a region first"
    placeholder.value = ""
    this.localeTarget.appendChild(placeholder)

    locales.forEach((locale) => {
      const option = document.createElement("option")
      option.value = locale
      option.textContent = locale
      this.localeTarget.appendChild(option)
    })
  }
}
