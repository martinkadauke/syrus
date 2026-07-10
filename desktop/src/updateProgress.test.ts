import { describe, expect, it } from "vitest"
import { BackendUpdateProgressTracker } from "../electron/installer/updateProgress"

const step = (id: string, status: string) => JSON.stringify({ event: "step", id, status })
const logLine = (line: string) => JSON.stringify({ event: "log", line })
const layer = (id: string, text: string, current?: number, total?: number) =>
  logLine(JSON.stringify({ id, text, current, total }))

describe("BackendUpdateProgressTracker", () => {
  it("begins in the starting phase with no percent", () => {
    expect(new BackendUpdateProgressTracker().snapshot()).toEqual({ phase: "starting", percent: null })
  })

  it("maps install.sh step starts onto the sidebar phases", () => {
    const tracker = new BackendUpdateProgressTracker()

    expect(tracker.observeLine(step("image_pull", "start"))).toEqual({ phase: "downloading", percent: null })
    expect(tracker.observeLine(step("stack_up", "start"))).toEqual({ phase: "starting", percent: null })
    expect(tracker.observeLine(step("health", "start"))).toEqual({ phase: "migrating", percent: null })
  })

  it("ignores steps the sidebar has no phase for, and non-start statuses", () => {
    const tracker = new BackendUpdateProgressTracker()

    expect(tracker.observeLine(step("env_check", "start"))).toBeNull()
    expect(tracker.observeLine(step("image_pull", "ok"))).toBeNull()
    expect(tracker.observeLine(step("health", "ok"))).toBeNull()
    expect(tracker.snapshot()).toEqual({ phase: "starting", percent: null })
  })

  it("folds wrapped compose pull progress into an overall percent while pulling", () => {
    const tracker = new BackendUpdateProgressTracker()
    tracker.observeLine(step("image_pull", "start"))

    expect(tracker.observeLine(layer("aaa", "Downloading", 250, 1000))).toEqual({ phase: "downloading", percent: 25 })
    expect(tracker.observeLine(layer("aaa", "Downloading", 420, 1000))).toEqual({ phase: "downloading", percent: 42 })
  })

  it("stays silent when the percent has not changed", () => {
    const tracker = new BackendUpdateProgressTracker()
    tracker.observeLine(step("image_pull", "start"))
    tracker.observeLine(layer("aaa", "Downloading", 420, 1000))

    // Same integer percent — a broadcast here would spam IPC for nothing.
    expect(tracker.observeLine(layer("aaa", "Downloading", 421, 1000))).toBeNull()
  })

  it("ignores pull progress outside the image_pull step", () => {
    const tracker = new BackendUpdateProgressTracker()

    expect(tracker.observeLine(layer("aaa", "Downloading", 500, 1000))).toBeNull()

    tracker.observeLine(step("image_pull", "start"))
    tracker.observeLine(step("image_pull", "ok"))
    expect(tracker.observeLine(layer("aaa", "Downloading", 990, 1000))).toBeNull()
  })

  it("drops the pull percent when a later phase begins", () => {
    const tracker = new BackendUpdateProgressTracker()
    tracker.observeLine(step("image_pull", "start"))
    tracker.observeLine(layer("aaa", "Downloading", 1000, 1000))

    expect(tracker.observeLine(step("stack_up", "start"))).toEqual({ phase: "starting", percent: null })
    expect(tracker.snapshot()).toEqual({ phase: "starting", percent: null })
  })

  it("folds unwrapped compose progress objects the same way the onboarding driver does", () => {
    const tracker = new BackendUpdateProgressTracker()
    tracker.observeLine(step("image_pull", "start"))

    expect(tracker.observeLine(JSON.stringify({ id: "aaa", text: "Downloading", current: 100, total: 1000 }))).toEqual({
      phase: "downloading",
      percent: 10
    })
  })

  it("treats plain text, malformed JSON, and other installer events as no change", () => {
    const tracker = new BackendUpdateProgressTracker()
    tracker.observeLine(step("image_pull", "start"))

    expect(tracker.observeLine("Pulling syrus-backend ...")).toBeNull()
    expect(tracker.observeLine("{not json")).toBeNull()
    expect(tracker.observeLine(JSON.stringify({ event: "error", code: 30, message: "boom" }))).toBeNull()
    expect(tracker.observeLine(JSON.stringify({ event: "done", url: "http://localhost:3000" }))).toBeNull()
    expect(tracker.snapshot()).toEqual({ phase: "downloading", percent: null })
  })
})
