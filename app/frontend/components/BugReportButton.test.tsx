import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { BugReportButton } from "./BugReportButton"
import type { BugReportPayload } from "../api/bugReports"

vi.mock("../api/bugReports", () => ({
  createBugReport: vi.fn()
}))

vi.mock("../lib/errorRingBuffer", () => ({
  getRecentErrors: vi.fn().mockReturnValue([])
}))

// html2canvas-pro is unavailable in jsdom; the openDialog catch block handles this
// and the dialog still opens via the finally block.
vi.mock("html2canvas-pro", () => ({
  default: vi.fn().mockRejectedValue(new Error("not supported in test env"))
}))

import { createBugReport } from "../api/bugReports"
import { getRecentErrors } from "../lib/errorRingBuffer"

const mockCreateBugReport = createBugReport as ReturnType<typeof vi.fn> & typeof createBugReport
const mockGetRecentErrors = getRecentErrors as ReturnType<typeof vi.fn>

function renderButton(props: {
  position?: "bottom-left" | "bottom-right"
  context?: string
  chatId?: number | null
  bugReportMode?: "direct_job" | "github_issue" | null
} = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  render(
    <QueryClientProvider client={client}>
      <BugReportButton context="Dashboard" {...props} />
    </QueryClientProvider>
  )
}

function getBugButton() {
  return screen.getByRole("button", { name: "Report a bug" })
}

async function openDialog() {
  fireEvent.click(screen.getByRole("button", { name: "Report a bug" }))
  await screen.findByRole("dialog")
}

describe("BugReportButton", () => {
  beforeEach(() => {
    mockCreateBugReport.mockResolvedValue({ message: "Bug report queued." } as BugReportPayload)
    mockGetRecentErrors.mockReturnValue([])
    localStorage.clear()
    Object.defineProperty(window, "innerWidth", { configurable: true, value: 1024 })
    Object.defineProperty(window, "innerHeight", { configurable: true, value: 768 })
    // jsdom does not implement pointer capture APIs; define no-ops so drag handlers work.
    Object.defineProperty(HTMLElement.prototype, "setPointerCapture", { configurable: true, writable: true, value: vi.fn() })
    Object.defineProperty(HTMLElement.prototype, "releasePointerCapture", { configurable: true, writable: true, value: vi.fn() })
  })

  afterEach(() => {
    vi.clearAllMocks()
    // Clean up prototype stubs defined above.
    delete (HTMLElement.prototype as unknown as Record<string, unknown>).setPointerCapture
    delete (HTMLElement.prototype as unknown as Record<string, unknown>).releasePointerCapture
  })

  it("is always visible — no hidden class", () => {
    renderButton()
    expect(getBugButton()).toBeInTheDocument()
    expect(getBugButton().className).not.toContain("hidden")
  })

  it("defaults to the bottom-right when no saved position exists", () => {
    renderButton()
    const button = getBugButton()
    const left = parseFloat(button.style.left)
    const top = parseFloat(button.style.top)
    // bottom-right: left near right edge, top near bottom
    expect(left).toBeGreaterThan(window.innerWidth / 2)
    expect(top).toBeGreaterThan(window.innerHeight / 2)
  })

  it("defaults to the bottom-left when position='bottom-left' and no saved position", () => {
    renderButton({ position: "bottom-left" })
    const button = getBugButton()
    const left = parseFloat(button.style.left)
    expect(left).toBeLessThan(window.innerWidth / 2)
  })

  it("loads a saved position from localStorage", () => {
    localStorage.setItem("bug-report-button-position", JSON.stringify({ left: 123, top: 456 }))
    renderButton()
    const button = getBugButton()
    expect(button.style.left).toBe("123px")
    expect(button.style.top).toBe("456px")
  })

  it("ignores malformed localStorage data and falls back to default", () => {
    localStorage.setItem("bug-report-button-position", "not-json{{{")
    renderButton()
    const button = getBugButton()
    // Should fall back to default (right side, bottom)
    expect(parseFloat(button.style.left)).toBeGreaterThan(0)
    expect(parseFloat(button.style.top)).toBeGreaterThan(0)
  })

  describe("tap vs drag threshold", () => {
    it("treats displacement below 8px as a tap and opens the dialog", async () => {
      renderButton()
      const button = getBugButton()

      fireEvent.pointerDown(button, { clientX: 200, clientY: 300, pointerId: 1 })
      // Move only 5px — below the 8px threshold
      fireEvent.pointerMove(button, { clientX: 204, clientY: 303, pointerId: 1 })
      fireEvent.pointerUp(button, { clientX: 204, clientY: 303, pointerId: 1 })

      await screen.findByRole("dialog")
    })

    it("treats displacement of exactly 0px as a tap and opens the dialog", async () => {
      renderButton()
      const button = getBugButton()

      fireEvent.pointerDown(button, { clientX: 200, clientY: 300, pointerId: 1 })
      fireEvent.pointerUp(button, { clientX: 200, clientY: 300, pointerId: 1 })

      await screen.findByRole("dialog")
    })

    it("treats displacement >= 8px as a drag and does not open the dialog", () => {
      renderButton()
      const button = getBugButton()

      fireEvent.pointerDown(button, { clientX: 200, clientY: 300, pointerId: 1 })
      fireEvent.pointerMove(button, { clientX: 210, clientY: 300, pointerId: 1 }) // 10px
      fireEvent.pointerUp(button, { clientX: 210, clientY: 300, pointerId: 1 })

      expect(screen.queryByRole("dialog")).not.toBeInTheDocument()
    })
  })

  describe("drag — position persistence", () => {
    it("saves the new position to localStorage after a drag", () => {
      localStorage.setItem("bug-report-button-position", JSON.stringify({ left: 200, top: 300 }))
      renderButton()
      const button = getBugButton()

      fireEvent.pointerDown(button, { clientX: 200, clientY: 300, pointerId: 1 })
      fireEvent.pointerMove(button, { clientX: 250, clientY: 320, pointerId: 1 })
      fireEvent.pointerUp(button, { clientX: 250, clientY: 320, pointerId: 1 })

      const saved = JSON.parse(localStorage.getItem("bug-report-button-position") ?? "null") as {
        left: number
        top: number
      } | null
      expect(saved).not.toBeNull()
      expect(saved!.left).toBeCloseTo(250, 0)
      expect(saved!.top).toBeCloseTo(320, 0)
    })

    it("clamps the saved position so the button stays within the viewport", () => {
      localStorage.setItem("bug-report-button-position", JSON.stringify({ left: 200, top: 300 }))
      renderButton()
      const button = getBugButton()

      // Drag far beyond the right/bottom edge
      fireEvent.pointerDown(button, { clientX: 200, clientY: 300, pointerId: 1 })
      fireEvent.pointerMove(button, { clientX: 9999, clientY: 9999, pointerId: 1 })
      fireEvent.pointerUp(button, { clientX: 9999, clientY: 9999, pointerId: 1 })

      const saved = JSON.parse(localStorage.getItem("bug-report-button-position") ?? "null") as {
        left: number
        top: number
      } | null
      expect(saved).not.toBeNull()
      // 1024 - 48 = 976; 768 - 48 = 720
      expect(saved!.left).toBeLessThanOrEqual(window.innerWidth - 48)
      expect(saved!.top).toBeLessThanOrEqual(window.innerHeight - 48)
    })

    it("clamps position to the top-left corner when dragged off-screen to the left/top", () => {
      localStorage.setItem("bug-report-button-position", JSON.stringify({ left: 200, top: 300 }))
      renderButton()
      const button = getBugButton()

      fireEvent.pointerDown(button, { clientX: 200, clientY: 300, pointerId: 1 })
      fireEvent.pointerMove(button, { clientX: -9999, clientY: -9999, pointerId: 1 })
      fireEvent.pointerUp(button, { clientX: -9999, clientY: -9999, pointerId: 1 })

      const saved = JSON.parse(localStorage.getItem("bug-report-button-position") ?? "null") as {
        left: number
        top: number
      } | null
      expect(saved).not.toBeNull()
      expect(saved!.left).toBeGreaterThanOrEqual(0)
      expect(saved!.top).toBeGreaterThanOrEqual(0)
    })
  })

  describe("keyboard access", () => {
    it("opens the dialog when the button receives a keyboard-triggered click", async () => {
      renderButton()
      const button = getBugButton()

      // A keyboard-triggered click is not preceded by pointer events,
      // so pointerHandledRef stays false and the click handler calls openDialog.
      fireEvent.click(button)

      await screen.findByRole("dialog")
    })

    it("does not open the dialog twice when both a pointer tap and the synthetic click fire", async () => {
      renderButton()
      const button = getBugButton()

      // Simulate a tap followed by the synthetic click the browser fires after pointerup.
      fireEvent.pointerDown(button, { clientX: 100, clientY: 100, pointerId: 1 })
      fireEvent.pointerUp(button, { clientX: 100, clientY: 100, pointerId: 1 })
      // Synthetic click that follows a real pointer tap:
      fireEvent.click(button)

      // Dialog should appear exactly once (not re-opened on the synthetic click).
      const dialogs = await screen.findAllByRole("dialog")
      expect(dialogs).toHaveLength(1)
    })
  })

  it("renders the trigger button", () => {
    renderButton()
    expect(screen.getByRole("button", { name: "Report a bug" })).toBeInTheDocument()
  })

  it("opens the dialog when button is clicked", async () => {
    renderButton()
    await openDialog()

    expect(screen.getByRole("dialog")).toBeInTheDocument()
    expect(screen.getByLabelText("Title")).toBeInTheDocument()
  })

  it("pre-fills the title with context + ' bug'", async () => {
    renderButton({ context: "Jobs" })
    await openDialog()

    expect(screen.getByLabelText("Title")).toHaveValue("Jobs bug")
  })

  it("renders the 'What's included' <details> element closed by default", async () => {
    renderButton()
    await openDialog()

    const summary = screen.getByText("What's included")
    const details = summary.closest("details")
    expect(details).toBeInTheDocument()
    expect(details).not.toHaveAttribute("open")
  })

  it("opens the 'What's included' section when the summary is clicked", async () => {
    renderButton()
    await openDialog()

    fireEvent.click(screen.getByText("What's included"))

    const details = screen.getByText("What's included").closest("details")
    expect(details).toHaveAttribute("open")
  })

  it("contains context fields (URL, Browser, Viewport, Recent JS errors)", async () => {
    renderButton()
    await openDialog()

    // Content is present in the DOM regardless of details open state
    expect(screen.getByText("URL:")).toBeInTheDocument()
    expect(screen.getByText("Browser:")).toBeInTheDocument()
    expect(screen.getByText("Viewport:")).toBeInTheDocument()
    expect(screen.getByText("Recent JS errors")).toBeInTheDocument()
    // no errors recorded; "None" also appears in the screenshot option, so use getAllByText
    expect(screen.getAllByText("None").length).toBeGreaterThanOrEqual(1)
  })

  it("shows recent errors in the preview when present", async () => {
    mockGetRecentErrors.mockReturnValue([
      { message: "TypeError: cannot read x", source: "app.js", at: "2025-01-01T00:00:00.000Z" }
    ])

    renderButton()
    await openDialog()

    expect(screen.getByText("TypeError: cannot read x")).toBeInTheDocument()
    expect(screen.getByText("(app.js)")).toBeInTheDocument()
  })

  it("shows the chat session row when chatId is provided", async () => {
    renderButton({ context: "Chat", chatId: 42 })
    await openDialog()

    expect(screen.getByText("Chat session:")).toBeInTheDocument()
    expect(screen.getByText("42")).toBeInTheDocument()
  })

  it("omits the chat session row when chatId is not provided", async () => {
    renderButton()
    await openDialog()

    expect(screen.queryByText("Chat session:")).not.toBeInTheDocument()
  })

  it("sends context JSON with the bug report submission", async () => {
    mockCreateBugReport.mockResolvedValue({ message: "Bug report queued." } satisfies BugReportPayload)
    mockGetRecentErrors.mockReturnValue([
      { message: "ReferenceError: x is not defined", source: "chunk.js", at: "2025-06-01T12:00:00.000Z" }
    ])

    renderButton({ context: "Admin" })
    await openDialog()

    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Test bug" } })
    fireEvent.submit(screen.getByRole("dialog").querySelector("form")!)

    await waitFor(() => expect(mockCreateBugReport).toHaveBeenCalledOnce())

    const call = mockCreateBugReport.mock.calls[0][0]
    expect(call.context).toBeDefined()

    const ctx = JSON.parse(call.context as string)
    expect(ctx.url).toBeDefined()
    expect(ctx.user_agent).toBeDefined()
    expect(ctx.viewport).toMatchObject({ width: expect.any(Number), height: expect.any(Number) })
    expect(ctx.device_pixel_ratio).toBeDefined()
    expect(ctx.recent_errors).toHaveLength(1)
    expect(ctx.recent_errors[0].message).toBe("ReferenceError: x is not defined")
  })

  it("includes chat_session_id in the submitted context JSON when chatId is provided", async () => {
    mockCreateBugReport.mockResolvedValue({ message: "Bug report queued." } satisfies BugReportPayload)

    renderButton({ context: "Chat", chatId: 99 })
    await openDialog()

    fireEvent.submit(screen.getByRole("dialog").querySelector("form")!)

    await waitFor(() => expect(mockCreateBugReport).toHaveBeenCalledOnce())

    const ctx = JSON.parse(mockCreateBugReport.mock.calls[0][0].context as string)
    expect(ctx.chat_session_id).toBe(99)
  })

  it("closes the dialog on cancel", async () => {
    renderButton()
    await openDialog()

    fireEvent.click(screen.getByRole("button", { name: "Cancel" }))

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument()
  })

  it("shows a queued notice on successful direct-job submission", async () => {
    mockCreateBugReport.mockResolvedValue({ message: "Bug report queued." } satisfies BugReportPayload)

    renderButton({ bugReportMode: "direct_job" })
    await openDialog()

    fireEvent.submit(screen.getByRole("dialog").querySelector("form")!)

    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument())
    expect(screen.getByRole("status")).toHaveTextContent("Bug report queued.")
  })
})
