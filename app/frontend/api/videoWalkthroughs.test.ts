import { describe, expect, it } from "vitest"
import {
  isWalkthroughVideoFile,
  MAX_WALKTHROUGH_BYTES,
  MAX_WALKTHROUGH_DURATION_SECONDS,
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
