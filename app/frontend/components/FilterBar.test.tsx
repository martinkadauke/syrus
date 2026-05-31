import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { MemoryRouter, useLocation } from "react-router-dom"
import { describe, expect, it } from "vitest"
import { FilterBar, type FilterSchemaField } from "./FilterBar"

const filterSchema: FilterSchemaField[] = [
  {
    field: "state",
    label: "State",
    bucket: "enum",
    operators: ["is"],
    values: [
      { value: "open", label: "Open" },
      { value: "closed", label: "Closed" }
    ]
  },
  {
    field: "kind",
    label: "Kind",
    bucket: "enum",
    operators: ["is"],
    values: [{ value: "issue", label: "Issue" }]
  },
  {
    field: "has_parent",
    label: "Has parent",
    bucket: "boolean",
    operators: ["is_true", "is_false"],
    values: []
  }
]

function LocationProbe() {
  const location = useLocation()
  return <output data-testid="location">{`${location.pathname}${location.search}`}</output>
}

function decodedFilterFromLocation() {
  const location = screen.getByTestId("location").textContent || ""
  const query = location.split("?")[1] || ""
  const q = new URLSearchParams(query).get("q")
  if (!q) return null

  const normalized = q.replace(/-/g, "+").replace(/_/g, "/")
  const base64 = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")
  const bytes = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0))
  return JSON.parse(new TextDecoder().decode(bytes))
}

describe("FilterBar", () => {
  it("applies chip editor value changes immediately", async () => {
    render(
      <MemoryRouter initialEntries={["/dashboard/jobs"]}>
        <FilterBar
          filter={{ and: [{ field: "state", op: "is", value: "open" }] }}
          filterSchema={filterSchema}
          pathname="/dashboard/jobs"
          search=""
        />
        <LocationProbe />
      </MemoryRouter>
    )

    fireEvent.click(screen.getByRole("button", { name: "State is Open" }))
    fireEvent.change(screen.getByLabelText("Value"), { target: { value: "closed" } })

    await waitFor(() => {
      expect(decodedFilterFromLocation()).toEqual({
        and: [{ field: "state", op: "is", value: "closed" }]
      })
    })
  })

  it("does not show a value placeholder for predicate filters", () => {
    render(
      <MemoryRouter initialEntries={["/dashboard/jobs"]}>
        <FilterBar
          filter={{ and: [{ field: "has_parent", op: "is_true", value: null }] }}
          filterSchema={filterSchema}
          pathname="/dashboard/jobs"
          search=""
        />
      </MemoryRouter>
    )

    fireEvent.click(screen.getByRole("button", { name: "Has parent is true" }))

    expect(screen.getByRole("dialog", { name: "Has parent filter settings" })).toBeInTheDocument()
    expect(screen.queryByText("No value needed")).not.toBeInTheDocument()
  })

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
    expect(screen.queryByRole("button", { name: "Apply filter" })).not.toBeInTheDocument()
    expect(screen.queryByRole("button", { name: "Done" })).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Add OR filter to State" }))

    await waitFor(() => {
      expect(screen.queryByRole("dialog", { name: "State filter settings" })).not.toBeInTheDocument()
    })
    expect(screen.getByPlaceholderText("Search filters...")).toBeInTheDocument()
  })

  it("closes an open chip editor with Escape or an outside click", () => {
    const { rerender } = render(
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
    fireEvent.keyDown(window, { key: "Escape" })
    expect(screen.queryByRole("dialog", { name: "State filter settings" })).not.toBeInTheDocument()

    rerender(
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
    fireEvent.pointerDown(document.body)
    expect(screen.queryByRole("dialog", { name: "State filter settings" })).not.toBeInTheDocument()
  })
})
