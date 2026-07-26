import { Controller } from "@hotwired/stimulus"

// Auto-suggests a technician's CALL-E region from their phone number's
// country code, and filters the spoken-language <select> to only the
// locales valid for the chosen region. See
// app/models/concerns/call_e_supported_regions.rb for the source of truth
// this mirrors (kept in sync via the JSON blob rendered in the view).
export default class extends Controller {
  static targets = ["phone", "region", "locale"]

  connect() {
    this.regionsData = JSON.parse(document.getElementById("call-e-regions-data").textContent)
    // Longest calling codes first, so e.g. "971" matches before "1"
    this.callingCodes = {
      "1": "US", "65": "SG", "60": "MY", "91": "IN", "971": "AE", "61": "AU",
      "44": "GB", "84": "VN", "49": "DE", "81": "JP", "33": "FR", "52": "MX",
      "55": "BR", "62": "ID", "63": "PH", "254": "KE"
    }
    this.sortedCodes = Object.keys(this.callingCodes).sort((a, b) => b.length - a.length)

    if (this.regionTarget.value) this.updateLocales()
  }

  suggestRegion() {
    const digits = this.phoneTarget.value.replace(/\D/g, "")
    const code = this.sortedCodes.find((c) => digits.startsWith(c))
    if (code && !this.regionTarget.value) {
      this.regionTarget.value = this.callingCodes[code]
      this.updateLocales()
    }
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
