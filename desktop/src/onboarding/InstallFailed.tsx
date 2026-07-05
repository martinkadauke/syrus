import { FooterRow, LogTail, OnboardingScreen } from "./primitives"

type InstallFailedProps = {
  code: number
  step: string | null
  message: string
  logTail: string[]
  onRetry: () => void
  onBack: () => void
}

const FRIENDLY_MESSAGES: Record<number, string> = {
  12: "Docker is available but Docker Compose isn't. OrbStack and Docker Desktop both bundle it — updating your runtime usually fixes this.",
  30: "Downloading the Syrus image failed. This usually means a network problem — check your connection and try again.",
  31: "The registry refused the Syrus image download — the package is private, this build's tag was never published, or this machine isn't logged in to ghcr.io. If this is a dev build, push the image (bin/build-local-image --push) or make the package public, then retry.",
  32: "This build references a Syrus image tag that doesn't exist in the registry — the image was never published for this build. If this is a dev build, push it with bin/build-local-image --push and retry.",
  40: "Docker Compose couldn't start the Syrus containers.",
  41: "The containers started, but Syrus never answered. It may still be booting — retrying is usually safe."
}

export function InstallFailed({ code, step, message, logTail, onRetry, onBack }: InstallFailedProps) {
  const friendly = FRIENDLY_MESSAGES[code]

  return (
    <OnboardingScreen title="Install didn't finish" titleTone="danger">
      <p className="mt-3 text-sm leading-relaxed text-slate-700">{friendly ?? message}</p>
      {friendly ? <p className="mt-2 text-xs text-slate-500">{message}</p> : null}
      {step ? (
        <p className="mt-1 text-xs text-slate-400">
          Failed during: {step} (exit {code})
        </p>
      ) : null}

      <LogTail lines={logTail} label="Show the last log lines" />

      <FooterRow>
        <button type="button" className="secondary-button" onClick={onBack}>
          Back
        </button>
        <button type="button" className="primary-button" onClick={onRetry}>
          Try again
        </button>
      </FooterRow>
    </OnboardingScreen>
  )
}
