import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { App } from "./App"

describe("App", () => {
  it("renders the SPA shell scaffold", () => {
    render(<App />)

    expect(screen.getByRole("main", { name: "Syrus SPA" })).toBeInTheDocument()
    expect(screen.getByText(/React shell scaffold/)).toBeInTheDocument()
  })
})
