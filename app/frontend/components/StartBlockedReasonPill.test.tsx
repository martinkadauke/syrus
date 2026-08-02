import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { StartBlockedReasonPill } from "./StartBlockedReasonPill"

describe("StartBlockedReasonPill", () => {
  it("renders main branch health blocks as red with an explanatory tooltip", () => {
    render(<StartBlockedReasonPill reason="main_branch_broken" />)

    const pill = screen.getByText("Main branch broken").closest("[data-status-pill]")
    expect(pill).toHaveClass("bg-red-50")
    expect(pill).toHaveAttribute("title", "Repository landing is paused because the main branch is unhealthy.")
  })

  it("renders urgent job blocks as slate", () => {
    render(<StartBlockedReasonPill reason="urgent_job_active" />)

    expect(screen.getByText("Urgent job in progress").closest("[data-status-pill]")).toHaveClass("bg-gray-100")
  })

  it("includes structured start-block details in the tooltip", () => {
    render(
      <StartBlockedReasonPill
        details={{
          message: "multiple dependency branches are ready",
          dependencies: [{ slug: "JOB-1574" }, { job_id: 1575 }],
          action: "Land the sibling dependencies."
        }}
        reason="stack_fan_in_base_unavailable"
      />
    )

    expect(screen.getByText("Fan-in base unavailable").closest("[data-status-pill]")).toHaveAttribute(
      "title",
      [
        "Multiple dependency PR branches are ready, but Syrus could not prepare a combined execution base.",
        "multiple dependency branches are ready",
        "Dependencies: JOB-1574, JOB-1575",
        "Land the sibling dependencies."
      ].join("\n")
    )
  })
})
