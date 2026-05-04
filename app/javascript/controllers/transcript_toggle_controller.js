import { Controller } from "@hotwired/stimulus"

// Toggles visibility of tool_call + tool_result rows in a per-Run
// transcript. Default state hides them — the operator usually
// wants the agent's narrative without the noise of every Bash /
// Read / tool_result. Click the toggle to reveal.
//
// Wires CSS via a `hide-tool-rows` class on the container; the
// CSS rule (in application.css) hides rows tagged with
// data-log-kind="tool_call" or "tool_result".
export default class extends Controller {
  static targets = ["container", "label"]
  static values = { showTools: { type: Boolean, default: false } }

  connect() {
    this.applyState()
  }

  toggle(event) {
    if (event) event.preventDefault()
    this.showToolsValue = !this.showToolsValue
    this.applyState()
  }

  // Hooked next to `toggle` on the click event so the same click
  // doesn't bubble up and toggle the surrounding <details>.
  stop(event) {
    event.stopPropagation()
  }

  applyState() {
    if (this.hasContainerTarget) {
      this.containerTarget.classList.toggle("hide-tool-rows", !this.showToolsValue)
    }
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.showToolsValue ? "Hide tool calls" : "Show tool calls"
    }
  }
}
