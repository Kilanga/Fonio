import { Controller } from "@hotwired/stimulus"

// Auto-submits the language switcher form on selection, so there's no
// separate "Go" button to tap — one less step on a small screen.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
