import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { PasswordMatchHint, PasswordStrengthMeter } from "./PasswordFeedback"

describe("PasswordStrengthMeter", () => {
  it("shows no label for an empty password", () => {
    render(<PasswordStrengthMeter password="" />)
    expect(screen.getByTestId("password-strength").textContent?.trim()).toBe("")
  })

  it("labels a strong passphrase and fills the segments", () => {
    render(<PasswordStrengthMeter password="Blue-Otter!Yodels@Dawn7" />)
    const meter = screen.getByTestId("password-strength")
    expect(meter.textContent).toContain("Strong")
    expect(meter.querySelectorAll(".bg-emerald-500").length).toBe(4)
  })

  it("labels a weak password with a single filled segment", () => {
    render(<PasswordStrengthMeter password="cat" />)
    const meter = screen.getByTestId("password-strength")
    expect(meter.textContent).toContain("Weak")
    expect(meter.querySelectorAll(".bg-red-400").length).toBe(1)
  })
})

describe("PasswordMatchHint", () => {
  it("stays invisible before the confirmation is touched", () => {
    render(<PasswordMatchHint confirmation="" password="secret" />)
    expect(screen.getByTestId("password-match").className).toContain("opacity-0")
  })

  it("confirms a match with the check", () => {
    render(<PasswordMatchHint confirmation="Blue-Otter7" password="Blue-Otter7" />)
    const hint = screen.getByTestId("password-match")
    expect(hint.textContent).toContain("Passwords match")
    expect(hint.className).toContain("text-emerald-600")
    expect(hint.querySelector("svg")).not.toBeNull()
  })

  it("hints gently while they differ", () => {
    render(<PasswordMatchHint confirmation="Blue-Ot" password="Blue-Otter7" />)
    const hint = screen.getByTestId("password-match")
    expect(hint.textContent).toContain("Doesn't match yet")
    expect(hint.className).toContain("text-amber-600")
  })
})
