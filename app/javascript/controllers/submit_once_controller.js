import { Controller } from "@hotwired/stimulus"

// Disables a button_to form's submit button as soon as it's submitted, so
// a slow connection (common out in the field) can't make someone think a
// tap didn't register and hit it again, double-submitting.
export default class extends Controller {
  submitting() {
    const button = this.element.querySelector("input[type=submit], button[type=submit]")
    if (!button) return
    button.disabled = true
    button.classList.add("opacity-60")
  }
}
