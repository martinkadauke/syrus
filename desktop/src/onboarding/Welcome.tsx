type WelcomeProps = {
  onChoose: (mode: "local" | "remote") => void
}

export function Welcome({ onChoose }: WelcomeProps) {
  return (
    <section className="w-full max-w-xl text-center">
      <h1 className="text-2xl font-semibold tracking-tight">Welcome to Syrus</h1>
      <p className="mt-2 text-sm text-slate-600">
        Syrus turns GitHub issues into reviewed pull requests. Where should it run?
      </p>

      <div className="mt-8 grid grid-cols-2 gap-4 text-left">
        <button
          type="button"
          onClick={() => onChoose("local")}
          className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm transition hover:border-blue-400 hover:shadow"
        >
          <span className="block text-base font-semibold text-slate-900">Install on this Mac</span>
          <span className="mt-2 block text-sm leading-relaxed text-slate-600">
            Runs Syrus locally in Docker. Everything stays on your machine — this app sets it all up.
          </span>
        </button>

        <button
          type="button"
          onClick={() => onChoose("remote")}
          className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm transition hover:border-blue-400 hover:shadow"
        >
          <span className="block text-base font-semibold text-slate-900">Connect to existing Syrus</span>
          <span className="mt-2 block text-sm leading-relaxed text-slate-600">
            Your team already runs Syrus somewhere? Point this app at its URL.
          </span>
        </button>
      </div>
    </section>
  )
}
