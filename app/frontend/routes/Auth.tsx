import { useMutation, useQuery } from "@tanstack/react-query"
import type { FormEvent, KeyboardEvent, ReactNode } from "react"
import { useEffect, useState } from "react"
import { Link, useLocation, useParams } from "react-router-dom"
import { authPrimaryButtonClass } from "../lib/buttonStyles"
import { NoticeToast } from "../components/NoticeToast"
import { CapsLockHint, EmailValidityHint, PasswordMatchHint, PasswordStrengthMeter } from "../components/PasswordFeedback"
import {
  fetchSignup,
  requestPasswordReset,
  resetPassword,
  signIn,
  signUp,
  type SignupPayload
} from "../api/auth"
import { errorMessage } from "../lib/errorMessage"

export function SignInRoute() {
  const location = useLocation()
  const prefix = routePrefix(location.pathname)
  const [emailAddress, setEmailAddress] = useState("")
  const [password, setPassword] = useState("")
  const [capsLock, setCapsLock] = useState(false)
  const submit = useMutation({
    mutationFn: () => signIn({ email_address: emailAddress, password }),
    onSuccess: (payload) => assignWithPrefix(prefix, payload.redirect_to)
  })

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    submit.mutate()
  }

  function trackCapsLock(event: KeyboardEvent<HTMLInputElement>) {
    setCapsLock(event.getModifierState("CapsLock"))
  }

  return (
    <AuthShell
      title="Sign in"
      subtitle="Use an existing Syrus account for this instance."
    >
      <form className="space-y-5" onSubmit={onSubmit}>
        {submit.isError ? <PanelMessage tone="error">{errorMessage(submit.error, "Unable to sign in.")}</PanelMessage> : null}
        <Field label="Email address">
          <input
            autoComplete="username"
            autoFocus
            className={inputClass()}
            onChange={(event) => setEmailAddress(event.target.value)}
            required
            type="email"
            value={emailAddress}
          />
          <EmailValidityHint email={emailAddress} />
        </Field>
        <Field label="Password">
          <input
            autoComplete="current-password"
            className={inputClass()}
            maxLength={72}
            onChange={(event) => setPassword(event.target.value)}
            onKeyDown={trackCapsLock}
            onKeyUp={trackCapsLock}
            required
            type="password"
            value={password}
          />
          <CapsLockHint active={capsLock} />
        </Field>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <button className={authPrimaryButtonClass} disabled={submit.isPending} type="submit">
            {submit.isPending ? "Signing in..." : "Sign in"}
          </button>
          <Link className="text-sm text-gray-700 dark:text-gray-300 underline hover:no-underline" to={`${prefix}/passwords/new`}>Forgot password?</Link>
        </div>
      </form>
    </AuthShell>
  )
}

export function SignUpRoute() {
  const location = useLocation()
  const prefix = routePrefix(location.pathname)
  const signup = useQuery({
    queryKey: ["auth", "signup", location.search],
    queryFn: () => fetchSignup(location.search)
  })

  return (
    <AuthShell
      title="Create account"
      subtitle="Join this Syrus instance with open sign-ups or an invitation link."
    >
      {signup.isPending ? <PanelMessage>Loading sign-up...</PanelMessage> : null}
      {signup.isError ? <PanelMessage tone="error">{errorMessage(signup.error, "Unable to load sign-up.")}</PanelMessage> : null}
      {signup.isSuccess ? <SignUpForm payload={signup.data} prefix={prefix} /> : null}
    </AuthShell>
  )
}

function SignUpForm({ payload, prefix }: { payload: SignupPayload; prefix: string }) {
  const [emailAddress, setEmailAddress] = useState(payload.invitation?.email_address || "")
  const [password, setPassword] = useState("")
  const [passwordConfirmation, setPasswordConfirmation] = useState("")
  const submit = useMutation({
    mutationFn: () => signUp({
      email_address: emailAddress,
      password,
      password_confirmation: passwordConfirmation,
      invitation_token: payload.invitation?.token
    }),
    onSuccess: (saved) => assignWithPrefix(prefix, saved.redirect_to)
  })

  useEffect(() => {
    setEmailAddress(payload.invitation?.email_address || "")
  }, [payload.invitation?.email_address])

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    submit.mutate()
  }

  if (!payload.allowed) {
    return (
      <PanelMessage tone="error">
        Sign-up is invitation-only. Use an invitation link or <Link className="underline hover:no-underline" to={`${prefix}/session/new`}>sign in</Link>.
      </PanelMessage>
    )
  }

  return (
    <form className="space-y-5" onSubmit={onSubmit}>
      {payload.invitation ? <PanelMessage>Accepting an invitation from {payload.invitation.invited_by_email}.</PanelMessage> : null}
      {payload.first_signup ? <PanelMessage>No users exist yet. This account will become the administrator.</PanelMessage> : null}
      {submit.isError ? <PanelMessage tone="error">{errorMessage(submit.error, "Unable to create account.")}</PanelMessage> : null}
      <Field label="Email address">
        <input
          autoComplete="username"
          autoFocus
          className={inputClass()}
          onChange={(event) => setEmailAddress(event.target.value)}
          required
          type="email"
          value={emailAddress}
        />
        <EmailValidityHint email={emailAddress} />
      </Field>
      <Field label="Password">
        <input
          autoComplete="new-password"
          className={inputClass()}
          maxLength={72}
          onChange={(event) => setPassword(event.target.value)}
          required
          type="password"
          value={password}
        />
        <PasswordStrengthMeter password={password} />
      </Field>
      <Field label="Confirm password">
        <input
          autoComplete="new-password"
          className={inputClass()}
          maxLength={72}
          onChange={(event) => setPasswordConfirmation(event.target.value)}
          required
          type="password"
          value={passwordConfirmation}
        />
        <PasswordMatchHint confirmation={passwordConfirmation} password={password} />
      </Field>
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
        <button className={authPrimaryButtonClass} disabled={submit.isPending} type="submit">
          {submit.isPending ? "Creating..." : "Create account"}
        </button>
        {/* No accounts exist yet on the first signup — nobody to sign in as. */}
        {payload.first_signup ? null : <Link className="text-sm text-gray-700 dark:text-gray-300 underline hover:no-underline" to={`${prefix}/session/new`}>Already have an account? Sign in</Link>}
      </div>
    </form>
  )
}

export function PasswordRequestRoute() {
  const location = useLocation()
  const prefix = routePrefix(location.pathname)
  const [emailAddress, setEmailAddress] = useState("")
  const [notice, setNotice] = useState<string | null>(null)
  const submit = useMutation({
    mutationFn: () => requestPasswordReset(emailAddress),
    onSuccess: (payload) => setNotice(payload.message)
  })

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setNotice(null)
    submit.mutate()
  }

  return (
    <AuthShell
      title="Reset password"
      subtitle="Enter the email address for your Syrus account."
    >
      <form className="space-y-5" onSubmit={onSubmit}>
        <NoticeToast message={notice} onDismiss={() => setNotice(null)} />
        {submit.isError ? <PanelMessage tone="error">{errorMessage(submit.error, "Unable to request password reset.")}</PanelMessage> : null}
        <Field label="Email address">
          <input
            autoComplete="username"
            autoFocus
            className={inputClass()}
            onChange={(event) => setEmailAddress(event.target.value)}
            required
            type="email"
            value={emailAddress}
          />
          <EmailValidityHint email={emailAddress} />
        </Field>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <button className={authPrimaryButtonClass} disabled={submit.isPending} type="submit">
            {submit.isPending ? "Sending..." : "Email reset instructions"}
          </button>
          <Link className="text-sm text-gray-700 dark:text-gray-300 underline hover:no-underline" to={`${prefix}/session/new`}>Back to sign in</Link>
        </div>
      </form>
    </AuthShell>
  )
}

export function PasswordResetRoute() {
  const params = useParams()
  const location = useLocation()
  const prefix = routePrefix(location.pathname)
  const token = params.token || ""
  const [password, setPassword] = useState("")
  const [passwordConfirmation, setPasswordConfirmation] = useState("")
  const submit = useMutation({
    mutationFn: () => resetPassword(token, { password, password_confirmation: passwordConfirmation }),
    onSuccess: (payload) => assignWithPrefix(prefix, payload.redirect_to)
  })

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    submit.mutate()
  }

  return (
    <AuthShell
      title="Update password"
      subtitle="Choose a new password for your Syrus account."
    >
      <form className="space-y-5" onSubmit={onSubmit}>
        {submit.isError ? <PanelMessage tone="error">{errorMessage(submit.error, "Unable to update password.")}</PanelMessage> : null}
        <Field label="New password">
          <input
            autoComplete="new-password"
            autoFocus
            className={inputClass()}
            maxLength={72}
            onChange={(event) => setPassword(event.target.value)}
            required
            type="password"
            value={password}
          />
          <PasswordStrengthMeter password={password} />
        </Field>
        <Field label="Confirm password">
          <input
            autoComplete="new-password"
            className={inputClass()}
            maxLength={72}
            onChange={(event) => setPasswordConfirmation(event.target.value)}
            required
            type="password"
            value={passwordConfirmation}
          />
          <PasswordMatchHint confirmation={passwordConfirmation} password={password} />
        </Field>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <button className={authPrimaryButtonClass} disabled={submit.isPending} type="submit">
            {submit.isPending ? "Saving..." : "Save"}
          </button>
          <Link className="text-sm text-gray-700 dark:text-gray-300 underline hover:no-underline" to={`${prefix}/session/new`}>Back to sign in</Link>
        </div>
      </form>
    </AuthShell>
  )
}

function AuthShell({ title, subtitle, children }: { title: string; subtitle?: string; children: ReactNode }) {
  // Vertically centered so sign-in reads as a proper entry screen (the
  // desktop shell lands here when signed out); the inner column keeps the
  // familiar max-w-xl card with left-aligned headings.
  return (
    <main aria-label={title} className="flex min-h-[70vh] flex-col items-center justify-center p-6">
      <div className="w-full max-w-xl space-y-6">
        <header>
          <h1 className="text-3xl font-semibold text-gray-900 dark:text-gray-100">{title}</h1>
          {subtitle ? <p className="mt-2 text-sm leading-6 text-gray-600 dark:text-gray-400">{subtitle}</p> : null}
        </header>
        <section className="rounded border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 p-5">
          {children}
        </section>
      </div>
    </main>
  )
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
      {label}
      <div className="mt-2">{children}</div>
    </label>
  )
}

function PanelMessage({ children, tone = "muted" }: { children: ReactNode; tone?: "muted" | "error" | "success" }) {
  const colors = {
    error: "border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-950/40 text-red-700 dark:text-red-300",
    success: "border-green-200 dark:border-green-800 bg-green-50 dark:bg-green-950/40 text-green-700 dark:text-green-300",
    muted: "border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800 text-gray-600 dark:text-gray-400"
  }

  return <div className={`rounded border p-3 text-sm ${colors[tone]}`}>{children}</div>
}

function inputClass() {
  return "block w-full rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-900 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 shadow-sm focus:outline-blue-600"
}

function routePrefix(pathname: string) {
  return pathname.startsWith("/app-shell") ? "/app-shell" : ""
}

// The JSON auth endpoints return app-root paths ("/onboarding", "/dashboard");
// when the SPA is mounted under /app-shell, keep the user inside that prefix
// instead of bouncing them out to the server-rendered root. Absolute URLs
// pass through verbatim — after_authentication_path can replay a stored
// request.url ("http://host/app-shell/jobs/5"), and gluing the prefix onto
// that would build a broken path. Exported for tests.
export function authRedirectTarget(prefix: string, path: string) {
  if (!prefix || !path.startsWith("/") || path.startsWith(prefix)) return path

  return `${prefix}${path}`
}

function assignWithPrefix(prefix: string, path: string) {
  window.location.assign(authRedirectTarget(prefix, path))
}

