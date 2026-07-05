type RuntimeSetupProps = {
  mode: "missing" | "starting"
  polling: boolean
  onDownload: () => void
  onRetry: () => void
  onBack: () => void
}

// Guided Docker-runtime acquisition: no Homebrew, no terminal. We point the
// user at OrbStack's DMG and poll until the daemon answers.
export function RuntimeSetup({ mode, polling, onDownload, onRetry, onBack }: RuntimeSetupProps) {
  if (mode === "starting") {
    return (
      <section className="w-full max-w-md text-center">
        <h1 className="text-xl font-semibold">Starting your Docker runtime…</h1>
        <p className="mt-3 text-sm leading-relaxed text-slate-600">
          The first launch can take a moment and may ask for a one-time permission — accept it if it does.
        </p>
        <p className="mt-4 text-sm text-slate-500" role="status">
          Waiting for Docker…
        </p>
        <button type="button" className="secondary-button mt-6" onClick={onBack}>
          Back
        </button>
      </section>
    )
  }

  return (
    <section className="w-full max-w-md">
      <h1 className="text-center text-xl font-semibold">One thing first: a Docker runtime</h1>
      <p className="mt-3 text-sm leading-relaxed text-slate-600">
        Syrus runs in containers, which needs a Docker runtime. We recommend{" "}
        <span className="font-medium text-slate-900">OrbStack</span> — it&apos;s fast, lightweight, and free
        for personal use. Docker Desktop works too.
      </p>

      <ol className="mt-5 list-decimal space-y-2 pl-5 text-sm leading-relaxed text-slate-600">
        <li>Download OrbStack and drag it into Applications.</li>
        <li>Open it once and finish its short setup.</li>
        <li>Come back here — we&apos;ll pick things up automatically.</li>
      </ol>

      {polling ? (
        <p className="mt-5 text-center text-sm text-slate-500" role="status">
          Waiting for Docker to become available…
        </p>
      ) : null}

      <div className="mt-6 flex justify-between">
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
            Download OrbStack
          </button>
        </div>
      </div>
    </section>
  )
}
