import { act, fireEvent, render, renderHook, screen, waitFor } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import {
  formatClock,
  pickRecorderMimeType,
  RECORDER_MIME_CANDIDATES,
  RECORDER_WARNING_SECONDS,
  useWalkthroughRecorder,
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

// The recorder derives durationSeconds from its OWN clock (Date.now at start
// vs stop), never by re-measuring the produced blob — a MediaRecorder webm's
// metadata duration is Infinity, so the wall-clock is the only reliable
// source for the ≥12-min gate. This exercises that onFinished contract.
class FakeMediaRecorder {
  static isTypeSupported = () => true
  ondataavailable: ((event: { data: Blob }) => void) | null = null
  onstop: (() => void) | null = null
  mimeType = "video/webm"
  start = vi.fn()
  stop = vi.fn(() => {
    this.ondataavailable?.({ data: new Blob(["chunk"], { type: "video/webm" }) })
    this.onstop?.()
  })
}

function fakeTrack() {
  return { stop: vi.fn(), addEventListener: vi.fn() }
}

function fakeStream() {
  const track = fakeTrack()
  return { getTracks: () => [track], getVideoTracks: () => [track], getAudioTracks: () => [track] } as unknown as MediaStream
}

describe("useWalkthroughRecorder onFinished", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  it("delivers a numeric durationSeconds derived from the wall clock, not the blob", async () => {
    const onFinished = vi.fn()
    let recorder: FakeMediaRecorder | null = null

    vi.stubGlobal("MediaRecorder", class extends FakeMediaRecorder {
      constructor() {
        super()
        recorder = this
      }
    })
    vi.stubGlobal("MediaStream", class {
      // The hook wraps the picked tracks in a fresh MediaStream — jsdom has none.
    })
    vi.stubGlobal("navigator", {
      ...navigator,
      mediaDevices: {
        getDisplayMedia: vi.fn().mockResolvedValue(fakeStream()),
        getUserMedia: vi.fn().mockResolvedValue(fakeStream())
      }
    })
    const nowSpy = vi.spyOn(Date, "now")
    nowSpy.mockReturnValue(1_000_000) // start clock

    const { result } = renderHook(() => useWalkthroughRecorder({ onFinished }))

    await act(async () => {
      await result.current.start()
    })
    expect(recorder).not.toBeNull()

    // 7.4s elapsed on the recorder's clock → rounds to 7.
    nowSpy.mockReturnValue(1_007_400)
    act(() => {
      result.current.stop()
    })

    await waitFor(() => expect(onFinished).toHaveBeenCalledTimes(1))
    const result0 = onFinished.mock.calls[0][0]
    expect(typeof result0.durationSeconds).toBe("number")
    expect(result0.durationSeconds).toBe(7)
    expect(result0.blob).toBeInstanceOf(Blob)
    expect(result0.mimeType).toBe("video/webm")

    vi.unstubAllGlobals()
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
