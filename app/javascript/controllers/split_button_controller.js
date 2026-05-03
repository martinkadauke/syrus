import { Controller } from "@hotwired/stimulus"

// Split button: a primary action with a chevron that toggles a
// dropdown of related options. Used by the partial
// `shared/_split_button.html.erb`.
//
// Closes on outside-click and Escape. The menu submit-buttons are
// real <form> POSTs (via button_to), so navigating away after
// submission unmounts this controller — no manual close needed.
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.boundOutside = this.handleOutsideClick.bind(this)
    this.boundEscape = this.handleEscape.bind(this)
    document.addEventListener("click", this.boundOutside)
    document.addEventListener("keydown", this.boundEscape)
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutside)
    document.removeEventListener("keydown", this.boundEscape)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
  }

  close() {
    this.menuTarget.classList.add("hidden")
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  handleEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
