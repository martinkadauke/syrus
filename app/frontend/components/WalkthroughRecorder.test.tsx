import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import {
  formatClock,
  pickRecorderMimeType,
  RECORDER_MIME_CANDIDATES,
  RECORDER_WARNING_SECONDS,
  WalkthroughRecorderHUD
} from "./WalkthroughRecorder"
import { MAX_WALKTHROUGH_DURATION_SECONDS } from "../api/videoWalkthroughs"

describe("formatClock", () => {
  it("renders zero as 0:00", () => {
    expect(formatClock(0)).toBe("0:00")
  })

  it("renders 61 seconds as 1:01", () => {
    expect(formatClock(61)).toBe("1:01")
  })

  it("renders the 900-second cap as 15:00", () => {
    expect(formatClock(900)).toBe("15:00")
  })

  it("clamps negative values to 0:00", () => {
    expect(formatClock(-1)).toBe("0:00")
    expect(formatClock(-900)).toBe("0:00")
  })
})

describe("pickRecorderMimeType", () => {
  it("prefers vp9 when everything is supported", () => {
    expect(pickRecorderMimeType(() => true)).toBe("video/webm;codecs=vp9,opus")
  })

  it("falls back to vp8 when vp9 is unsupported", () => {
    expect(pickRecorderMimeType((type) => !type.includes("vp9"))).toBe("video/webm;codecs=vp8,opus")
  })

  it("falls back to plain webm when no codec-specific type is supported", () => {
    expect(pickRecorderMimeType((type) => !type.includes("codecs"))).toBe("video/webm")
  })

  it("falls back to mp4 when only mp4 is supported", () => {
    expect(pickRecorderMimeType((type) => type === "video/mp4")).toBe("video/mp4")
  })

  it("returns null when nothing is supported", () => {
    expect(pickRecorderMimeType(() => false)).toBeNull()
  })

  it("probes the candidates in preference order", () => {
    expect(RECORDER_MIME_CANDIDATES).toEqual([
      "video/webm;codecs=vp9,opus",
      "video/webm;codecs=vp8,opus",
      "video/webm",
      "video/mp4"
    ])
  })
})

const hudLabels = {
  recording: "Recording",
  noMic: "No microphone",
  stop: "Stop",
  discard: "Discard",
  remaining: (clock: string) => `${clock} left`
}

function renderHud(props: { elapsed?: number; micLive?: boolean; onStop?: () => void; onDiscard?: () => void } = {}) {
  return render(
    <WalkthroughRecorderHUD
      elapsed={props.elapsed ?? 0}
      labels={hudLabels}
      micLive={props.micLive ?? true}
      onDiscard={props.onDiscard ?? (() => {})}
      onStop={props.onStop ?? (() => {})}
    />
  )
}

describe("WalkthroughRecorderHUD", () => {
  it("shows the elapsed clock and remaining countdown", () => {
    renderHud({ elapsed: 61 })

    expect(screen.getByTestId("walkthrough-recorder-hud")).toHaveTextContent("Recording 1:01")
    // 900 - 61 = 839 seconds = 13:59 remaining.
    expect(screen.getByTestId("walkthrough-recorder-remaining")).toHaveTextContent("13:59 left")
  })

  it("keeps the countdown neutral before the final-minute warning", () => {
    renderHud({ elapsed: RECORDER_WARNING_SECONDS - 1 })

    expect(screen.getByTestId("walkthrough-recorder-remaining").className).not.toContain("text-amber-600")
  })

  it("turns the countdown amber at the warning threshold", () => {
    renderHud({ elapsed: RECORDER_WARNING_SECONDS })

    const remaining = screen.getByTestId("walkthrough-recorder-remaining")
    expect(remaining).toHaveTextContent(`${formatClock(MAX_WALKTHROUGH_DURATION_SECONDS - RECORDER_WARNING_SECONDS)} left`)
    expect(remaining.className).toContain("text-amber-600")
  })

  it("stays amber past the threshold", () => {
    renderHud({ elapsed: RECORDER_WARNING_SECONDS + 30 })

    expect(screen.getByTestId("walkthrough-recorder-remaining").className).toContain("text-amber-600")
  })

  it("fires the stop callback", () => {
    const onStop = vi.fn()
    renderHud({ onStop })

    fireEvent.click(screen.getByRole("button", { name: "Stop" }))
    expect(onStop).toHaveBeenCalledTimes(1)
  })

  it("fires the discard callback", () => {
    const onDiscard = vi.fn()
    renderHud({ onDiscard })

    fireEvent.click(screen.getByRole("button", { name: "Discard" }))
    expect(onDiscard).toHaveBeenCalledTimes(1)
  })

  it("shows the no-mic label only when the mic is not live", () => {
    const { unmount } = renderHud({ micLive: false })
    expect(screen.getByText("No microphone")).toBeInTheDocument()
    unmount()

    renderHud({ micLive: true })
    expect(screen.queryByText("No microphone")).not.toBeInTheDocument()
  })
})
