import { useState } from "react"

type AdoptExistingProps = {
  onLocateEnv: () => void
  onWipe: () => void
  onBack: () => void
}

// The encryption-key guard, in plain language. A previous install's data
// volume exists, but its .env (which holds the keys that can decrypt that
// data) isn't where this app keeps it. Never regenerate keys silently.
export function AdoptExisting({ onLocateEnv, onWipe, onBack }: AdoptExistingProps) {
  const [confirmation, setConfirmation] = useState("")
  const wipeArmed = confirmation.trim().toLowerCase() === "delete"

  return (
    <section className="w-full max-w-md">
      <h1 className="text-center text-xl font-semibold">Found an existing Syrus installation</h1>
      <p className="mt-3 text-sm leading-relaxed text-slate-600">
        This Mac already has Syrus data from a previous install (for example from running{" "}
        <code className="rounded bg-slate-100 px-1 py-0.5 text-xs">install.sh</code> in a checkout). That
        data is encrypted with keys stored in that install&apos;s{" "}
        <code className="rounded bg-slate-100 px-1 py-0.5 text-xs">.env</code> file. To keep your existing
        Jobs, repositories, and credentials, point us at it.
      </p>

      <div className="mt-6 rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
        <p className="text-sm font-medium text-slate-900">Keep my data</p>
        <p className="mt-1 text-sm text-slate-600">
          Locate the original <code className="rounded bg-slate-100 px-1 py-0.5 text-xs">.env</code> — we
          copy it, never move it.
        </p>
        <button type="button" className="primary-button mt-3" onClick={onLocateEnv}>
          Locate .env…
        </button>
      </div>

      <div className="mt-4 rounded-xl border border-red-200 bg-white p-4 shadow-sm">
        <p className="text-sm font-medium text-red-700">Start fresh instead</p>
        <p className="mt-1 text-sm text-slate-600">
          Permanently deletes the previous install&apos;s database, clone cache, and search index. Type{" "}
          <span className="font-semibold">delete</span> to enable.
        </p>
        <div className="mt-3 flex gap-2">
          <input
            type="text"
            value={confirmation}
            placeholder="delete"
            aria-label="Type delete to confirm"
            onChange={(event) => setConfirmation(event.target.value)}
            className="w-32 rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-sm shadow-sm focus:border-red-500 focus:outline-none"
          />
          <button
            type="button"
            disabled={!wipeArmed}
            onClick={onWipe}
            className="rounded-lg border border-red-300 bg-white px-3 py-1.5 text-sm font-medium text-red-700 shadow-sm transition enabled:hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-40"
          >
            Delete all Syrus data
          </button>
        </div>
      </div>

      <div className="mt-6 text-center">
        <button type="button" className="secondary-button" onClick={onBack}>
          Back
        </button>
      </div>
    </section>
  )
}
