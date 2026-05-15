import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["stream", "newMessagesPill", "textarea", "sendButton", "stopButton", "whiteboard", "whiteboardPlaceholder"]
  static values = {
    turnInFlight: Boolean,
    olderMessagesUrl: String,
    hasMoreOlder: Boolean,
  }

  connect() {
    this.wasNearBottom = true
    this.loadingOlder = false
    // Defer the initial scroll one frame so any layout work the
    // sibling controllers do during their own connect — chat-layout
    // reparents this pane into a slot, which resets scrollTop — has
    // settled before we anchor to the bottom. Fall back to a sync
    // call in the JS unit test env where rAF is undefined.
    if (typeof requestAnimationFrame === "function") {
      requestAnimationFrame(() => this.scrollToBottom())
    } else {
      this.scrollToBottom()
    }
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
    if (this.isNearTop()) this.loadOlderMessages()
  }

  isNearTop() {
    if (!this.hasStreamTarget) return false
    return this.streamTarget.scrollTop < 120
  }

  async loadOlderMessages() {
    if (this.loadingOlder) return
    if (!this.hasMoreOlderValue) return
    if (!this.hasOlderMessagesUrlValue || !this.olderMessagesUrlValue) return
    if (!this.hasStreamTarget) return

    const first = this.streamTarget.querySelector("[data-message-id]")
    if (!first) return
    const beforeId = first.dataset.messageId
    if (!beforeId) return

    this.loadingOlder = true
    try {
      const response = await fetch(`${this.olderMessagesUrlValue}?before=${encodeURIComponent(beforeId)}`, {
        headers: { Accept: "text/html" },
        credentials: "same-origin",
      })
      if (!response.ok) return

      const hasMoreHeader = response.headers.get("X-Chat-Has-More-Older")
      if (hasMoreHeader !== null) {
        this.hasMoreOlderValue = hasMoreHeader === "true"
      }

      const html = await response.text()
      if (!html.trim()) return

      // Preserve the user's visual scroll position: prepending taller
      // content would otherwise leave them looking at a different
      // section of the conversation.
      const prevScrollHeight = this.streamTarget.scrollHeight
      const prevScrollTop = this.streamTarget.scrollTop
      first.insertAdjacentHTML("beforebegin", html)
      this.streamTarget.scrollTop = prevScrollTop + (this.streamTarget.scrollHeight - prevScrollHeight)
    } finally {
      this.loadingOlder = false
    }
  }

  messagesChanged() {
    // Prepending older messages also fires the mutation observer.
    // Don't auto-scroll or surface the "new messages" pill in that
    // case — the change happened above the viewport, not below.
    if (this.loadingOlder) return

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
