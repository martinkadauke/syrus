import { passwordStrength } from "../lib/passwordStrength"

// Live feedback under the password fields on signup / password reset:
// a four-segment entropy meter that fills and recolors as the password
// grows, and a match hint that fades in on the confirmation field.
// Guidance only — neither blocks submission.

const BAR_COLORS: Record<number, string> = {
  1: "bg-red-400",
  2: "bg-amber-400",
  3: "bg-emerald-400",
  4: "bg-emerald-500"
}

const LABEL_COLORS: Record<number, string> = {
  1: "text-red-600 dark:text-red-400",
  2: "text-amber-600 dark:text-amber-400",
  3: "text-emerald-600 dark:text-emerald-400",
  4: "text-emerald-600 dark:text-emerald-400"
}

export function PasswordStrengthMeter({ password }: { password: string }) {
  const strength = passwordStrength(password)

  return (
    <div aria-live="polite" className="mt-2" data-testid="password-strength">
      <div className="flex gap-1">
        {[1, 2, 3, 4].map((segment) => (
          <div
            className={`h-1 flex-1 rounded-full transition-colors duration-300 ${
              segment <= strength.score ? BAR_COLORS[strength.score] : "bg-gray-200 dark:bg-gray-700"
            }`}
            key={segment}
          />
        ))}
      </div>
      {/* Non-breaking space keeps the line height stable so the form doesn't jump. */}
      <p className={`mt-1 text-xs transition-colors duration-300 ${LABEL_COLORS[strength.score] ?? "text-gray-400"}`}>
        {strength.label || " "}
      </p>
    </div>
  )
}

export function PasswordMatchHint({ password, confirmation }: { password: string; confirmation: string }) {
  const match = confirmation.length > 0 && password === confirmation
  const mismatch = confirmation.length > 0 && !match

  return (
    <p
      aria-live="polite"
      className={`mt-1 flex items-center gap-1.5 text-xs transition-opacity duration-300 ${
        match
          ? "text-emerald-600 dark:text-emerald-400 opacity-100"
          : mismatch
            ? "text-amber-600 dark:text-amber-400 opacity-100"
            : "opacity-0"
      }`}
      data-testid="password-match"
    >
      {match ? (
        <svg aria-hidden="true" className="h-3.5 w-3.5" fill="none" stroke="currentColor" strokeWidth="2.5" viewBox="0 0 24 24">
          <path d="M5 13l4 4L19 7" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      ) : null}
      {match ? "Passwords match" : mismatch ? "Doesn't match yet" : " "}
    </p>
  )
}
