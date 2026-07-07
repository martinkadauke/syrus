import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import {
  isWalkthroughVideoFile,
  MAX_WALKTHROUGH_BYTES,
  MAX_WALKTHROUGH_DURATION_SECONDS,
  measureVideoDuration,
  WALKTHROUGH_CONTENT_TYPES
} from "./videoWalkthroughs"

describe("isWalkthroughVideoFile", () => {
  it("accepts webm video files", () => {
    expect(isWalkthroughVideoFile(new File([""], "walkthrough.webm", { type: "video/webm" }))).toBe(true)
  })

  it("accepts mp4 video files", () => {
    expect(isWalkthroughVideoFile(new File([""], "walkthrough.mp4", { type: "video/mp4" }))).toBe(true)
  })

  it("accepts a content type carrying codec parameters", () => {
    expect(isWalkthroughVideoFile(new File([""], "walkthrough.webm", { type: "video/webm;codecs=vp9,opus" }))).toBe(true)
  })

  it("rejects non-video files", () => {
    expect(isWalkthroughVideoFile(new File([""], "screenshot.png", { type: "image/png" }))).toBe(false)
    expect(isWalkthroughVideoFile(new File([""], "notes.txt", { type: "text/plain" }))).toBe(false)
  })
})

// jsdom does not implement media elements, so measureVideoDuration's
// <video> never fires metadata events on its own. Stub document.createElement
// so the returned fake exposes settable onloadedmetadata/onerror/src plus a
// controllable `duration`, then fire the handler the code wired up. This is
// the seam for the review finding: Chrome's MediaRecorder webm reports
// duration=Infinity, which must round-trip to null so recorded videos don't
// bypass the ≥12-min low-resolution gate with a bogus finite duration.
type FakeVideo = {
  preload: string
  src: string
  duration: number
  onloadedmetadata: (() => void) | null
  onerror: (() => void) | null
}

describe("measureVideoDuration", () => {
  let fakeVideo: FakeVideo
  let realCreateElement: typeof document.createElement

  beforeEach(() => {
    fakeVideo = { preload: "", src: "", duration: NaN, onloadedmetadata: null, onerror: null }
    realCreateElement = document.createElement.bind(document)
    vi.spyOn(document, "createElement").mockImplementation((tagName: string, options?: unknown) => {
      if (tagName === "video") return fakeVideo as unknown as HTMLElement
      return realCreateElement(tagName, options as ElementCreationOptions | undefined)
    })
    // URL.createObjectURL/revokeObjectURL are not implemented in jsdom.
    vi.stubGlobal("URL", {
      ...URL,
      createObjectURL: vi.fn(() => "blob:fake"),
      revokeObjectURL: vi.fn()
    })
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  function measureWith(fire: (video: FakeVideo) => void): Promise<number | null> {
    const promise = measureVideoDuration(new File([""], "walkthrough.webm", { type: "video/webm" }))
    fire(fakeVideo)
    return promise
  }

  it("returns null when metadata reports Infinity (Chrome MediaRecorder webm)", async () => {
    const result = await measureWith((video) => {
      video.duration = Infinity
      video.onloadedmetadata?.()
    })
    expect(result).toBeNull()
  })

  it("returns null for a zero-length duration", async () => {
    const result = await measureWith((video) => {
      video.duration = 0
      video.onloadedmetadata?.()
    })
    expect(result).toBeNull()
  })

  it("returns null for a negative duration", async () => {
    const result = await measureWith((video) => {
      video.duration = -5
      video.onloadedmetadata?.()
    })
    expect(result).toBeNull()
  })

  it("returns the rounded duration for a finite positive value", async () => {
    const result = await measureWith((video) => {
      video.duration = 42.4
      video.onloadedmetadata?.()
    })
    expect(result).toBe(42)
  })

  it("returns null when the element errors before metadata loads", async () => {
    const result = await measureWith((video) => {
      video.onerror?.()
    })
    expect(result).toBeNull()
  })

  it("revokes the object URL after resolving", async () => {
    await measureWith((video) => {
      video.duration = 30
      video.onloadedmetadata?.()
    })
    expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:fake")
  })
})

// These constants mirror ChatVideoWalkthrough::MAX_DURATION_SECONDS and
// ::MAX_FILE_SIZE — the server-side gates are pinned by
// spec/models/chat_video_walkthrough_spec.rb; this keeps the client copy
// from drifting.
describe("walkthrough upload gates", () => {
  it("caps duration at 15 minutes (900 seconds), matching the backend", () => {
    expect(MAX_WALKTHROUGH_DURATION_SECONDS).toBe(900)
  })

  it("caps size at 500 MB (524288000 bytes), matching the backend", () => {
    expect(MAX_WALKTHROUGH_BYTES).toBe(524_288_000)
  })

  it("allows exactly the recorder- and screen-capture-producible containers", () => {
    expect(WALKTHROUGH_CONTENT_TYPES).toEqual(["video/webm", "video/mp4", "video/quicktime"])
  })
})
