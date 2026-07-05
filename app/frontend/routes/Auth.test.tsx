import { fireEvent, render, screen } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { describe, expect, it } from "vitest"
import { MemoryRouter, Route, Routes } from "react-router-dom"
import type { ReactNode } from "react"
import { authRedirectTarget, PasswordRequestRoute, PasswordResetRoute, SignInRoute } from "./Auth"

function renderAt(path: string, routePath: string, element: ReactNode) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route element={element} path={routePath} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>
  )
}

// jsdom KeyboardEventInit support for modifier flags varies; overriding
// getModifierState on a hand-built event is deterministic. React's synthetic
// event delegates getModifierState to the native event.
function pressKey(element: Element, type: "keydown" | "keyup", capsLock: boolean) {
  const event = new KeyboardEvent(type, { bubbles: true, cancelable: true, key: "a" })
  Object.defineProperty(event, "getModifierState", {
    value: (key: string) => key === "CapsLock" && capsLock
  })
  fireEvent(element, event)
}

describe("SignInRoute", () => {
  it("shows the live email validity hint while typing", () => {
    renderAt("/session/new", "/session/new", <SignInRoute />)

    const hint = screen.getByTestId("email-validity")
    // Query the input once: after typing, the hint text joins the label's
    // accessible name, so the plain "Email address" lookup stops matching.
    const email = screen.getByLabelText("Email address")
    expect(hint.className).toContain("opacity-0")

    fireEvent.change(email, { target: { value: "ada@example" } })
    expect(hint.textContent).toContain("Doesn't look like an email address yet")

    fireEvent.change(email, { target: { value: "ada@example.org" } })
    expect(hint.textContent).toContain("Looks good")
  })

  it("surfaces a caps lock warning under the password field", () => {
    renderAt("/session/new", "/session/new", <SignInRoute />)

    const password = screen.getByLabelText("Password")
    const hint = screen.getByTestId("caps-lock")
    expect(hint.className).toContain("opacity-0")

    pressKey(password, "keydown", true)
    expect(hint.textContent).toContain("Caps Lock is on")
    expect(hint.className).toContain("text-amber-600")

    pressKey(password, "keyup", false)
    expect(hint.className).toContain("opacity-0")
  })
})

describe("PasswordRequestRoute", () => {
  it("shows the live email validity hint while typing", () => {
    renderAt("/passwords/new", "/passwords/new", <PasswordRequestRoute />)

    const hint = screen.getByTestId("email-validity")
    expect(hint.className).toContain("opacity-0")

    fireEvent.change(screen.getByLabelText("Email address"), { target: { value: "ada@example.org" } })
    expect(hint.textContent).toContain("Looks good")
  })
})

describe("PasswordResetRoute", () => {
  it("offers a way back to sign in", () => {
    renderAt("/passwords/reset-token/edit", "/passwords/:token/edit", <PasswordResetRoute />)

    expect(screen.getByRole("link", { name: "Back to sign in" })).toHaveAttribute("href", "/session/new")
  })

  it("keeps the back link inside the /app-shell prefix", () => {
    renderAt("/app-shell/passwords/reset-token/edit", "/app-shell/passwords/:token/edit", <PasswordResetRoute />)

    expect(screen.getByRole("link", { name: "Back to sign in" })).toHaveAttribute("href", "/app-shell/session/new")
  })
})

describe("authRedirectTarget", () => {
  it("keeps app-root redirects inside the /app-shell prefix", () => {
    expect(authRedirectTarget("/app-shell", "/dashboard")).toBe("/app-shell/dashboard")
  })

  it("leaves already-prefixed paths alone", () => {
    expect(authRedirectTarget("/app-shell", "/app-shell/onboarding")).toBe("/app-shell/onboarding")
  })

  it("passes absolute URLs through verbatim", () => {
    // after_authentication_path can replay session[:return_to_after_authenticating],
    // which is stored as the full request.url; prefixing it would build
    // "/app-shellhttp://..." and 404.
    expect(authRedirectTarget("/app-shell", "http://127.0.0.1:3000/app-shell/jobs/5"))
      .toBe("http://127.0.0.1:3000/app-shell/jobs/5")
  })

  it("is a no-op outside the shell", () => {
    expect(authRedirectTarget("", "/dashboard")).toBe("/dashboard")
  })
})
