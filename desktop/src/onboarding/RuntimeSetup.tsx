import { FooterRow, OnboardingScreen, Spinner } from "./primitives"

type RuntimeSetupProps = {
  mode: "missing" | "starting"
  polling: boolean
  onDownload: () => void
  onRetry: () => void
  onBack: () => void
}

// Guided Docker-runtime acquisition: no Homebrew, no terminal. We point the
// user at the recommended runtime's installer and poll until the daemon
// answers. The recommendation is per-platform: OrbStack on macOS, Docker
// Desktop on Windows.
export function RuntimeSetup({ mode, polling, onDownload, onRetry, onBack }: RuntimeSetupProps) {
  const isWindows = (window.syrusDesktop?.platform ?? "darwin") === "win32"
  const runtimeName = isWindows ? "Docker Desktop" : "OrbStack"

  if (mode === "starting") {
    return (
      <OnboardingScreen
        title="Starting your Docker runtime…"
        subtitle="The first launch can take a moment and may ask for a one-time permission — accept it if it does."
      >
        <p className="mt-4 flex items-center justify-center gap-2 text-sm text-slate-500" role="status">
          <Spinner />
          Waiting for Docker…
        </p>
        <FooterRow>
          <button type="button" className="secondary-button" onClick={onBack}>
            Back
          </button>
        </FooterRow>
      </OnboardingScreen>
    )
  }

  return (
    <OnboardingScreen
      title="One thing first: a Docker runtime"
      subtitle="Syrus runs in containers, which needs a Docker runtime."
    >
      <p className="mt-4 text-sm leading-relaxed text-slate-600">
        {isWindows ? (
          <>
            We recommend <span className="font-medium text-slate-900">Docker Desktop</span> — its installer
            sets up WSL 2 for you. Podman Desktop works too.
          </>
        ) : (
          <>
            We recommend <span className="font-medium text-slate-900">OrbStack</span> — it&apos;s fast,
            lightweight, and free for personal use. Docker Desktop works too.
          </>
        )}
      </p>

      <ol className="mt-5 list-decimal space-y-2 pl-5 text-sm leading-relaxed text-slate-600">
        <li>
          {isWindows
            ? `Download ${runtimeName} and run its installer.`
            : `Download ${runtimeName} and drag it into Applications.`}
        </li>
        <li>Open it once and finish its short setup.</li>
        <li>Come back here — we&apos;ll pick things up automatically.</li>
      </ol>

      {polling ? (
        <p className="mt-5 flex items-center justify-center gap-2 text-sm text-slate-500" role="status">
          <Spinner />
          Waiting for Docker to become available…
        </p>
      ) : null}

      <FooterRow>
        <button type="button" className="secondary-button" onClick={onBack}>
          Back
        </button>
        <div className="flex gap-2">
          {polling ? (
            <button type="button" className="secondary-button" onClick={onRetry}>
              Check again now
            </button>
          ) : null}
          <button type="button" className="primary-button" onClick={onDownload}>
            Download {runtimeName}
          </button>
        </div>
      </FooterRow>
    </OnboardingScreen>
  )
}
