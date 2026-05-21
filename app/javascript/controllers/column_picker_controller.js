import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

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
    this.panelTarget.classList.toggle("hidden")
  }

  close() {
    this.panelTarget.classList.add("hidden")
  }

  async save(event) {
    event.preventDefault()

    // The picker no longer renders a <form> wrapper (which would
    // illegally nest inside the bulk-actions form on /dashboard/jobs).
    // Build the FormData manually from the controls within
    // this.element. action URL + subject are carried on the root
    // element's data attributes.
    const url = this.element.dataset.columnPickerEndpoint
    const subject = this.element.dataset.columnPickerSubject
    const body = new FormData()
    body.append("subject", subject)
    this.element.querySelectorAll("input[type=checkbox][name='visible_columns[]']:checked").forEach((cb) => {
      body.append("visible_columns[]", cb.value)
    })

    const response = await fetch(url, {
      method: "PATCH",
      headers: {
        "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
      },
      body
    })

    if (response.ok) {
      this.close()
      window.Turbo?.visit(window.location.href, { action: "replace" })
    }
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  handleEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
