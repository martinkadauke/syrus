import { useState, type FormEvent } from "react"

type ConnectRemoteProps = {
  error: string | null
  busy: boolean
  checkingUrl?: string
  onSubmit: (url: string, token?: string) => void
  onBack: () => void
}

export function ConnectRemote({ error, busy, checkingUrl, onSubmit, onBack }: ConnectRemoteProps) {
  const [url, setUrl] = useState(checkingUrl ?? "")
  const [token, setToken] = useState("")

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!busy) {
      onSubmit(url, token.trim() === "" ? undefined : token)
    }
  }

  return (
    <section className="w-full max-w-md">
      <h1 className="text-center text-xl font-semibold">Connect to your Syrus</h1>
      <p className="mt-2 text-center text-sm text-slate-600">
        Enter the URL of the Syrus instance your team runs.
      </p>

      <form className="mt-6 space-y-4" onSubmit={handleSubmit}>
        <label className="block">
          <span className="text-sm font-medium text-slate-700">Instance URL</span>
          <input
            type="url"
            required
            value={url}
            disabled={busy}
            placeholder="https://syrus.your-company.dev"
            onChange={(event) => setUrl(event.target.value)}
            className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm focus:border-blue-500 focus:outline-none"
          />
        </label>

        <details className="rounded-lg border border-slate-200 bg-white px-3 py-2">
          <summary className="cursor-pointer text-sm text-slate-600">
            API token (optional — enables menu-bar notifications now)
          </summary>
          <input
            type="password"
            value={token}
            disabled={busy}
            placeholder="syrus_…"
            onChange={(event) => setToken(event.target.value)}
            className="mt-2 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm focus:border-blue-500 focus:outline-none"
          />
          <p className="mt-1 text-xs text-slate-500">
            Without a token you can still sign in in the app window; the menu-bar widget connects once
            you&apos;re signed in.
          </p>
        </details>

        {error ? <p className="text-sm text-red-600">{error}</p> : null}

        <div className="flex justify-between pt-2">
          <button type="button" className="secondary-button" disabled={busy} onClick={onBack}>
            Back
          </button>
          <button type="submit" className="primary-button" disabled={busy}>
            {busy ? "Connecting…" : "Connect"}
          </button>
        </div>
      </form>
    </section>
  )
}
