import { useCallback, useEffect, useRef, useState } from "react"
import { MAX_WALKTHROUGH_DURATION_SECONDS } from "../api/videoWalkthroughs"

// In-chat screen recording for walkthrough videos. getDisplayMedia gives the
// browser's native Meet-style picker; the mic rides along as a separate
// getUserMedia track so the user's narration is captured (Gemini ingests the
// audio track natively — narration is half the signal). The recorder gates
// GENTLY: a visible countdown with a warning at T-60s and a friendly
// auto-stop at the 15:00 cap, never a surprise error.

// Codec preference: VP9 handles static UI + text well at low bitrates and is
// always available in Chrome/Electron (software encoder). MP4/H.264 exists
// only where an OS encoder does — probe, never assume. Exported for tests.
export const RECORDER_MIME_CANDIDATES = [
  "video/webm;codecs=vp9,opus",
  "video/webm;codecs=vp8,opus",
  "video/webm",
  "video/mp4"
]

export function pickRecorderMimeType(
  isSupported: (type: string) => boolean = (type) =>
    typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported(type)
): string | null {
  return RECORDER_MIME_CANDIDATES.find((candidate) => isSupported(candidate)) ?? null
}

// Gemini samples video at 1 fps, so >15 fps is wasted bytes; 1080p cap +
// 2.5 Mbps yields ~20 MB/min → a full 15:00 recording ≈ 300 MB, inside the
// 500 MB upload gate with margin.
export const RECORDER_VIDEO_CONSTRAINTS: MediaTrackConstraints = {
  width: { max: 1920 },
  height: { max: 1080 },
  frameRate: { ideal: 10, max: 15 }
}
export const RECORDER_VIDEO_BITS_PER_SECOND = 2_500_000
export const RECORDER_AUDIO_BITS_PER_SECOND = 128_000
export const RECORDER_WARNING_SECONDS = MAX_WALKTHROUGH_DURATION_SECONDS - 60

export function formatClock(totalSeconds: number): string {
  const clamped = Math.max(0, Math.floor(totalSeconds))
  const minutes = Math.floor(clamped / 60)
  const seconds = clamped % 60
  return `${minutes}:${String(seconds).padStart(2, "0")}`
}

export type RecordingResult = {
  blob: Blob
  mimeType: string
  durationSeconds: number
}

type RecorderState =
  | { phase: "idle" }
  | { phase: "starting" }
  | { phase: "recording"; startedAt: number; micLive: boolean }
  | { phase: "error"; message: string }

export function useWalkthroughRecorder({ onFinished }: { onFinished: (result: RecordingResult) => void }) {
  const [state, setState] = useState<RecorderState>({ phase: "idle" })
  const [elapsed, setElapsed] = useState(0)
  const recorderRef = useRef<MediaRecorder | null>(null)
  const streamsRef = useRef<MediaStream[]>([])
  const chunksRef = useRef<Blob[]>([])
  const tickRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const startedAtRef = useRef(0)
  const finishedRef = useRef(false)

  const cleanup = useCallback(() => {
    if (tickRef.current) {
      clearInterval(tickRef.current)
      tickRef.current = null
    }
    streamsRef.current.forEach((stream) => stream.getTracks().forEach((track) => track.stop()))
    streamsRef.current = []
    recorderRef.current = null
  }, [])

  const stop = useCallback((options: { discard?: boolean } = {}) => {
    const recorder = recorderRef.current
    if (!recorder || finishedRef.current) {
      cleanup()
      setState({ phase: "idle" })
      setElapsed(0)
      return
    }

    finishedRef.current = true
    if (options.discard) {
      recorder.ondataavailable = null
      recorder.onstop = null
      try {
        recorder.stop()
      } catch {
        // already inactive — fine
      }
      cleanup()
      setState({ phase: "idle" })
      setElapsed(0)
      return
    }

    try {
      recorder.stop() // onstop assembles + delivers the result
    } catch {
      cleanup()
      setState({ phase: "error", message: "Recording could not be finalized." })
    }
  }, [cleanup])

  const start = useCallback(async () => {
    if (state.phase === "recording" || state.phase === "starting") return

    setState({ phase: "starting" })
    finishedRef.current = false
    chunksRef.current = []

    let display: MediaStream
    try {
      display = await navigator.mediaDevices.getDisplayMedia({
        video: RECORDER_VIDEO_CONSTRAINTS,
        audio: false
      })
    } catch {
      // User dismissed the picker (or the platform denied capture) — back to
      // idle silently; the picker itself was the confirmation surface.
      setState({ phase: "idle" })
      return
    }

    // Narration mic — requested AFTER the display picker so a mic denial
    // never blocks the recording; a walkthrough without narration is still
    // analyzable (Gemini flags ambiguities as open questions).
    let micLive = false
    let mic: MediaStream | null = null
    try {
      mic = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
      })
      micLive = true
    } catch {
      mic = null
    }

    const tracks = [ ...display.getVideoTracks(), ...(mic ? mic.getAudioTracks() : []) ]
    const combined = new MediaStream(tracks)
    streamsRef.current = [ display, ...(mic ? [mic] : []) ]

    const mimeType = pickRecorderMimeType()
    let recorder: MediaRecorder
    try {
      recorder = new MediaRecorder(combined, {
        ...(mimeType ? { mimeType } : {}),
        videoBitsPerSecond: RECORDER_VIDEO_BITS_PER_SECOND,
        audioBitsPerSecond: RECORDER_AUDIO_BITS_PER_SECOND
      })
    } catch {
      cleanup()
      setState({ phase: "error", message: "This browser cannot record the screen. Drag a video file in instead." })
      return
    }

    recorder.ondataavailable = (event) => {
      if (event.data.size > 0) chunksRef.current.push(event.data)
    }
    recorder.onstop = () => {
      const durationSeconds = Math.max(1, Math.round((Date.now() - startedAtRef.current) / 1000))
      const type = recorder.mimeType || mimeType || "video/webm"
      const blob = new Blob(chunksRef.current, { type: type.split(";")[0] })
      cleanup()
      setState({ phase: "idle" })
      setElapsed(0)
      onFinished({ blob, mimeType: type.split(";")[0], durationSeconds })
    }

    // Ending the share from the browser's own "Stop sharing" bar must finish
    // the recording, not orphan it.
    display.getVideoTracks()[0]?.addEventListener("ended", () => {
      if (!finishedRef.current && recorderRef.current) {
        finishedRef.current = true
        recorderRef.current.stop()
      }
    })

    recorderRef.current = recorder
    startedAtRef.current = Date.now()
    recorder.start(1_000) // 1s timeslices so a crash loses at most a second
    setElapsed(0)
    setState({ phase: "recording", startedAt: startedAtRef.current, micLive })

    tickRef.current = setInterval(() => {
      const seconds = Math.round((Date.now() - startedAtRef.current) / 1000)
      setElapsed(seconds)
      if (seconds >= MAX_WALKTHROUGH_DURATION_SECONDS && !finishedRef.current && recorderRef.current) {
        // The gentle gate: at 15:00 the recording completes as a SUCCESS.
        finishedRef.current = true
        recorderRef.current.stop()
      }
    }, 500)
  }, [state.phase, cleanup, onFinished])

  useEffect(() => () => cleanup(), [cleanup])

  return { state, elapsed, start, stop }
}

// The floating HUD while recording: pulsing dot, elapsed clock, remaining
// countdown that turns amber in the final minute, stop + discard controls.
export function WalkthroughRecorderHUD({
  elapsed,
  micLive,
  onStop,
  onDiscard,
  labels
}: {
  elapsed: number
  micLive: boolean
  onStop: () => void
  onDiscard: () => void
  labels: { recording: string; noMic: string; stop: string; discard: string; remaining: (clock: string) => string }
}) {
  const remaining = MAX_WALKTHROUGH_DURATION_SECONDS - elapsed
  const finalMinute = elapsed >= RECORDER_WARNING_SECONDS

  return (
    <div
      className="fixed bottom-6 left-1/2 z-50 flex -translate-x-1/2 items-center gap-3 rounded-full border border-gray-200 bg-white px-4 py-2 shadow-xl dark:border-gray-700 dark:bg-gray-900"
      data-testid="walkthrough-recorder-hud"
      role="status"
    >
      <span aria-hidden="true" className="relative flex h-3 w-3">
        <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-red-400 opacity-75" />
        <span className="relative inline-flex h-3 w-3 rounded-full bg-red-600" />
      </span>
      <span className="text-sm font-medium tabular-nums text-gray-900 dark:text-gray-100">
        {labels.recording} {formatClock(elapsed)}
      </span>
      <span
        className={`text-xs tabular-nums ${finalMinute ? "font-semibold text-amber-600 dark:text-amber-400" : "text-gray-500 dark:text-gray-400"}`}
        data-testid="walkthrough-recorder-remaining"
      >
        {labels.remaining(formatClock(remaining))}
      </span>
      {!micLive ? (
        <span className="text-xs text-amber-600 dark:text-amber-400" title={labels.noMic}>
          {labels.noMic}
        </span>
      ) : null}
      <button
        className="rounded-full bg-red-600 px-3 py-1 text-xs font-semibold text-white hover:bg-red-700"
        onClick={onStop}
        type="button"
      >
        {labels.stop}
      </button>
      <button
        className="rounded-full px-2 py-1 text-xs text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-800"
        onClick={onDiscard}
        type="button"
      >
        {labels.discard}
      </button>
    </div>
  )
}
