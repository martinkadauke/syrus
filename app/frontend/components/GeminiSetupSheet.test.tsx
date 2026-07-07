import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { beforeEach, describe, expect, it, vi } from "vitest"
import { GeminiSetupSheet, looksLikeGeminiKey } from "./GeminiSetupSheet"
import { testGeminiKey, updateCredentials } from "../api/credentials"

vi.mock("../api/credentials", () => ({
  testGeminiKey: vi.fn(),
  updateCredentials: vi.fn()
}))

// The staged validation deliberately pauses (~350ms per stage plus a 600ms
// beat before onConfigured) so the checks read as a cascade — give async
// assertions headroom beyond waitFor's 1s default.
const STAGE_TIMEOUT = { timeout: 4000 }

const labels = {
  title: "Set up Gemini",
  intro: "Walkthrough videos are analyzed with Gemini.",
  getKey: "Get a free API key",
  keyPlaceholder: "Paste your Gemini API key",
  validateAndSave: "Validate and save",
  validating: "Validating...",
  stageFormat: "Key format",
  stageReach: "Google reachability",
  stageVideo: "Video-capable model",
  saved: "Key saved.",
  keyHelp: "That does not look like a Gemini API key."
}

const VALID_KEY = "AIzaSy0123456789abcdefghijklmn" // 30 chars, no spaces

function renderSheet(props: { onClose?: () => void; onConfigured?: () => void } = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={client}>
      <GeminiSetupSheet labels={labels} onClose={props.onClose ?? (() => {})} onConfigured={props.onConfigured ?? (() => {})} />
    </QueryClientProvider>
  )
}

function submitKey(key: string) {
  fireEvent.change(screen.getByPlaceholderText(labels.keyPlaceholder), { target: { value: key } })
  fireEvent.click(screen.getByRole("button", { name: labels.validateAndSave }))
}

describe("looksLikeGeminiKey", () => {
  it("rejects short strings", () => {
    expect(looksLikeGeminiKey("AIza123")).toBe(false)
    expect(looksLikeGeminiKey("")).toBe(false)
  })

  it("rejects strings containing spaces", () => {
    expect(looksLikeGeminiKey("AIza followed by words and words")).toBe(false)
  })

  it("rejects email addresses", () => {
    expect(looksLikeGeminiKey("walkthrough.videos@example-corp.com")).toBe(false)
  })

  it("accepts a 30-character machine token", () => {
    expect(VALID_KEY).toHaveLength(30)
    expect(looksLikeGeminiKey(VALID_KEY)).toBe(true)
  })

  it("tolerates surrounding whitespace on an otherwise valid key", () => {
    expect(looksLikeGeminiKey(`  ${VALID_KEY}  `)).toBe(true)
  })
})

describe("GeminiSetupSheet", () => {
  beforeEach(() => {
    vi.mocked(testGeminiKey).mockReset()
    vi.mocked(updateCredentials).mockReset()
  })

  it("validates a good key end-to-end: stages cascade to ok, saves, and fires onConfigured", async () => {
    vi.mocked(testGeminiKey).mockResolvedValue({
      credential_test: {
        credential: "gemini_api_key",
        ok: true,
        message: "Gemini key works.",
        details: { model: "gemini-2.5-flash" } as never
      }
    })
    vi.mocked(updateCredentials).mockResolvedValue({} as never)
    const onConfigured = vi.fn()
    renderSheet({ onConfigured })

    expect(screen.getByTestId("gemini-stage-format")).toHaveAttribute("data-status", "pending")
    submitKey(VALID_KEY)

    await waitFor(() => expect(screen.getByTestId("gemini-stage-format")).toHaveAttribute("data-status", "ok"), STAGE_TIMEOUT)
    await waitFor(() => expect(screen.getByTestId("gemini-stage-reach")).toHaveAttribute("data-status", "ok"), STAGE_TIMEOUT)
    await waitFor(() => expect(screen.getByTestId("gemini-stage-video")).toHaveAttribute("data-status", "ok"), STAGE_TIMEOUT)

    expect(await screen.findByRole("status", {}, STAGE_TIMEOUT)).toHaveTextContent("Key saved.")
    expect(testGeminiKey).toHaveBeenCalledWith(VALID_KEY)
    expect(updateCredentials).toHaveBeenCalledWith({ gemini_api_key: VALID_KEY })
    await waitFor(() => expect(onConfigured).toHaveBeenCalledTimes(1), STAGE_TIMEOUT)
  })

  it("marks the reach stage failed and skips the save when Google rejects the key", async () => {
    vi.mocked(testGeminiKey).mockResolvedValue({
      credential_test: {
        credential: "gemini_api_key",
        ok: false,
        message: "Google rejected this key.",
        details: {}
      }
    })
    const onConfigured = vi.fn()
    renderSheet({ onConfigured })

    submitKey(VALID_KEY)

    await waitFor(() => expect(screen.getByTestId("gemini-stage-reach")).toHaveAttribute("data-status", "failed"), STAGE_TIMEOUT)
    expect(screen.getByRole("alert")).toHaveTextContent("Google rejected this key.")
    expect(screen.getByTestId("gemini-stage-video")).toHaveAttribute("data-status", "pending")
    expect(updateCredentials).not.toHaveBeenCalled()
    expect(onConfigured).not.toHaveBeenCalled()
  })

  it("fails the format stage locally without calling the API for an obvious paste accident", async () => {
    const onConfigured = vi.fn()
    renderSheet({ onConfigured })

    submitKey("not a key")

    await waitFor(() => expect(screen.getByTestId("gemini-stage-format")).toHaveAttribute("data-status", "failed"), STAGE_TIMEOUT)
    expect(screen.getByRole("alert")).toHaveTextContent(labels.keyHelp)
    expect(testGeminiKey).not.toHaveBeenCalled()
    expect(updateCredentials).not.toHaveBeenCalled()
    expect(onConfigured).not.toHaveBeenCalled()
  })

  it("validates immediately on paste, mirroring the Claude connector (no button click)", async () => {
    vi.mocked(testGeminiKey).mockResolvedValue({
      credential_test: { credential: "gemini_api_key", ok: true, message: "Gemini key works.", details: { model: "gemini-3.5-flash" } as never }
    })
    vi.mocked(updateCredentials).mockResolvedValue({} as never)
    const onConfigured = vi.fn()
    renderSheet({ onConfigured })

    // Paste directly, without clicking Validate & save.
    const input = screen.getByPlaceholderText(labels.keyPlaceholder)
    fireEvent.paste(input, { clipboardData: { getData: () => VALID_KEY } })

    await waitFor(() => expect(testGeminiKey).toHaveBeenCalledWith(VALID_KEY), STAGE_TIMEOUT)
    await waitFor(() => expect(onConfigured).toHaveBeenCalledTimes(1), STAGE_TIMEOUT)
  })
})
