import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { MemoryRouter } from "react-router-dom"
import { describe, expect, it } from "vitest"
import { FilterBar, type FilterSchemaField } from "./FilterBar"

const filterSchema: FilterSchemaField[] = [
  {
    field: "state",
    label: "State",
    bucket: "enum",
    operators: ["is"],
    values: [{ value: "open", label: "Open" }]
  },
  {
    field: "kind",
    label: "Kind",
    bucket: "enum",
    operators: ["is"],
    values: [{ value: "issue", label: "Issue" }]
  }
]

describe("FilterBar", () => {
  it("closes an open chip editor before showing the add-or filter menu", async () => {
    render(
      <MemoryRouter initialEntries={["/dashboard/jobs"]}>
        <FilterBar
          filter={{ and: [{ field: "state", op: "is", value: "open" }] }}
          filterSchema={filterSchema}
          pathname="/dashboard/jobs"
          search=""
        />
      </MemoryRouter>
    )

    fireEvent.click(screen.getByRole("button", { name: "State is Open" }))
    expect(screen.getByRole("dialog", { name: "State filter settings" })).toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Add OR filter to State" }))

    await waitFor(() => {
      expect(screen.queryByRole("dialog", { name: "State filter settings" })).not.toBeInTheDocument()
    })
    expect(screen.getByPlaceholderText("Search filters...")).toBeInTheDocument()
  })
})
