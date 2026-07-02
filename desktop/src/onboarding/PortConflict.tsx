import { useState } from "react"

type PortConflictProps = {
  port: number
  onContinue: (port: number) => void
  onBack: () => void
}

export function PortConflict({ port, onContinue, onBack }: PortConflictProps) {
  const [draft, setDraft] = useState(String(port === 3000 ? 3939 : port + 1))
  const parsed = Number.parseInt(draft, 10)
  const valid = Number.isFinite(parsed) && parsed > 1023 && parsed < 65536

  return (
    <section className="w-full max-w-md text-center">
      <h1 className="text-xl font-semibold">Port {port} is taken</h1>
      <p className="mt-3 text-sm leading-relaxed text-slate-600">
        Something else on this Mac is already using port {port} (often a development server). Pick another
        port for Syrus.
      </p>

      <div className="mt-6 flex items-center justify-center gap-2">
        <label className="text-sm text-slate-700" htmlFor="syrus-port">
          Serve Syrus on port
        </label>
        <input
          id="syrus-port"
          type="number"
          min={1024}
          max={65535}
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          className="w-24 rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-sm shadow-sm focus:border-blue-500 focus:outline-none"
        />
      </div>

      <div className="mt-6 flex justify-center gap-2">
        <button type="button" className="secondary-button" onClick={onBack}>
          Back
        </button>
        <button type="button" className="primary-button" disabled={!valid} onClick={() => onContinue(parsed)}>
          Continue
        </button>
      </div>
    </section>
  )
}
