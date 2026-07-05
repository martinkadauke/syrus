import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { EmailValidityHint } from "./PasswordFeedback"

describe("EmailValidityHint", () => {
  it("stays invisible while empty", () => {
    render(<EmailValidityHint email="" />)
    expect(screen.getByTestId("email-validity").className).toContain("opacity-0")
  })

  it("confirms a plausible address", () => {
    render(<EmailValidityHint email="ada@example.org" />)
    const hint = screen.getByTestId("email-validity")
    expect(hint.textContent).toContain("Looks good")
    expect(hint.className).toContain("text-emerald-600")
    expect(hint.querySelector("svg")).not.toBeNull()
  })

  it("hints gently at an incomplete address", () => {
    render(<EmailValidityHint email="ada@example" />)
    const hint = screen.getByTestId("email-validity")
    expect(hint.textContent).toContain("Doesn't look like an email address yet")
    expect(hint.className).toContain("text-amber-600")
  })
})
