import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["stream", "newMessagesPill", "textarea", "sendButton", "stopButton", "whiteboard", "whiteboardPlaceholder"]
  static values = { turnInFlight: Boolean }

  connect() {
    this.wasNearBottom = true
    this.scrollToBottom()
    this.updateCompose()
    this.syncWhiteboardPlaceholder()
    if (this.hasStreamTarget) {
      this.observer = new MutationObserver(() => this.messagesChanged())
      this.observer.observe(this.streamTarget, { childList: true })
    }
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  turnInFlightValueChanged() {
    this.updateCompose()
  }

  whiteboardTargetConnected() {
    this.syncWhiteboardPlaceholder()
  }

  textareaTargetConnected() {
    this.autoGrow()
  }

  autoGrow() {
    if (!this.hasTextareaTarget) return

    const ta = this.textareaTarget
    // Reset to auto so the next read of scrollHeight reflects current
    // content rather than the previously-set height; the CSS max-h on
    // the element caps growth, after which the textarea scrolls.
    ta.style.height = "auto"
    ta.style.height = `${ta.scrollHeight}px`
  }

  scroll() {
    this.wasNearBottom = this.isNearBottom()
    if (this.wasNearBottom) this.hideNewMessagesPill()
  }

  messagesChanged() {
    if (this.wasNearBottom || this.isNearBottom()) {
      this.scrollToBottom()
    } else {
      this.showNewMessagesPill()
    }
  }

  scrollToBottom() {
    if (!this.hasStreamTarget) return

    this.streamTarget.scrollTop = this.streamTarget.scrollHeight
    this.wasNearBottom = true
    this.hideNewMessagesPill()
  }

  updateCompose() {
    const disabled = this.turnInFlightValue
    if (this.hasTextareaTarget) this.textareaTarget.disabled = disabled
    if (this.hasSendButtonTarget) this.sendButtonTarget.disabled = disabled
  }

  stop() {
    if (!this.hasStopButtonTarget) return

    this.stopButtonTarget.disabled = true
    this.stopButtonTarget.value = "Stopping…"
    this.stopButtonTarget.textContent = "Stopping…"
  }

  whiteboardChanged(event) {
    const elements = event.detail?.elements || []
    this.setWhiteboardPlaceholderVisible(elements.length === 0)
  }

  syncWhiteboardPlaceholder() {
    if (!this.hasWhiteboardTarget) return

    try {
      const scene = JSON.parse(this.whiteboardTarget.dataset.whiteboardScene || "{}")
      const elements = Array.isArray(scene.elements) ? scene.elements : []
      this.setWhiteboardPlaceholderVisible(elements.length === 0)
    } catch {
      this.setWhiteboardPlaceholderVisible(true)
    }
  }

  isNearBottom() {
    if (!this.hasStreamTarget) return true

    return this.streamTarget.scrollHeight - this.streamTarget.scrollTop - this.streamTarget.clientHeight < 64
  }

  showNewMessagesPill() {
    if (this.hasNewMessagesPillTarget) this.newMessagesPillTarget.classList.remove("hidden")
  }

  hideNewMessagesPill() {
    if (this.hasNewMessagesPillTarget) this.newMessagesPillTarget.classList.add("hidden")
  }

  setWhiteboardPlaceholderVisible(visible) {
    if (this.hasWhiteboardPlaceholderTarget) this.whiteboardPlaceholderTarget.classList.toggle("hidden", !visible)
  }
}
