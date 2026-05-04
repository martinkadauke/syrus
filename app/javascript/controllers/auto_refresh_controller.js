import { Controller } from "@hotwired/stimulus"

// Re-fetches the current page on a timer via Turbo.visit with
// `action: replace` so the morph-mode layout (turbo_refreshes_with
// method: :morph) preserves expanded <details>, scroll position,
// data-turbo-permanent regions, etc.
//
// Pauses while the tab is hidden so a backgrounded admin overview
// doesn't keep polling. Resumes on visibility change.
//
// Markup:
//   <body data-controller="auto-refresh"
//         data-auto-refresh-interval-value="30">
//
// Optional: a clickable element with data-action="auto-refresh#refreshNow"
// triggers an immediate refresh + resets the timer.
export default class extends Controller {
  static values = { interval: { type: Number, default: 30 } }

  connect() {
    this.boundVisibility = this.handleVisibility.bind(this)
    document.addEventListener("visibilitychange", this.boundVisibility)
    this.scheduleNext()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.boundVisibility)
    this.clearTimer()
  }

  refreshNow(event) {
    if (event) event.preventDefault()
    this.clearTimer()
    Turbo.visit(window.location, { action: "replace" })
    // Don't reschedule here — the next page boot will reconnect
    // the controller and call scheduleNext() fresh.
  }

  scheduleNext() {
    this.clearTimer()
    if (document.hidden) return  // resume on visibility change
    this.timer = setTimeout(() => this.refreshNow(), this.intervalValue * 1000)
  }

  handleVisibility() {
    if (document.hidden) {
      this.clearTimer()
    } else {
      this.scheduleNext()
    }
  }

  clearTimer() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }
}
