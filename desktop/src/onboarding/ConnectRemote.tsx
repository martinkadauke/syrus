import { useMemo, useState, type FormEvent } from "react"
import { analyzeInstanceUrl } from "./instanceUrl"
import { FooterRow, FormError, OnboardingScreen, Spinner, ValidationHint } from "./primitives"

type ConnectRemoteProps = {
  error: string | null
  busy: boolean
  checkingUrl?: string
  onSubmit: (url: string) => void
  onBack: () => void
}

// Connect takes only the instance URL. There is deliberately no API-token
// field here: signing in inside the app window mints the tray token
// automatically (tokenProvisioner), and the manual-token path for non-admin
// accounts lives in Preferences where it can be revisited any time.
export function ConnectRemote({ error, busy, checkingUrl, onSubmit, onBack }: ConnectRemoteProps) {
  const [url, setUrl] = useState(checkingUrl ?? "")
  const analysis = useMemo(() => analyzeInstanceUrl(url), [url])

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!busy) {
      onSubmit(url.trim())
    }
  }

  return (
    <OnboardingScreen
      title="Connect to your Syrus"
      subtitle="Enter the address of the Syrus instance your team runs."
    >
      <form className="mt-6 space-y-4" onSubmit={handleSubmit}>
        <label className="block">
          <span>Instance address</span>
          <input
            type="text"
            inputMode="url"
            autoFocus
            required
            value={url}
            disabled={busy}
            placeholder="192.168.4.21:3000 or https://syrus.your-company.dev"
            onChange={(event) => setUrl(event.target.value)}
            spellCheck={false}
            autoCapitalize="off"
            autoCorrect="off"
          />
          <ValidationHint
            state={
              analysis.state === "invalid"
                ? "invalid"
                : analysis.state === "assumed"
                  ? "note"
                  : analysis.state === "ready"
                    ? "valid"
                    : "empty"
            }
          >
            {analysis.hint}
          </ValidationHint>
        </label>

        <FormError>{error}</FormError>

        <FooterRow>
          {/* Back stays enabled while checking so a black-holed host is never a dead end. */}
          <button type="button" className="secondary-button" onClick={onBack}>
            Back
          </button>
          <button
            type="submit"
            className="primary-button inline-flex items-center gap-2"
            disabled={busy || analysis.state === "invalid" || analysis.state === "empty"}
          >
            {busy ? (
              <>
                <Spinner />
                Connecting…
              </>
            ) : (
              "Connect"
            )}
          </button>
        </FooterRow>
      </form>
    </OnboardingScreen>
  )
}
