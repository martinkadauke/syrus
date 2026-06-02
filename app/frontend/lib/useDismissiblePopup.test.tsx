import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { useDismissiblePopup } from "./useDismissiblePopup"

function PopupHarness({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ref = useDismissiblePopup<HTMLDivElement>(open, onClose)

  return (
    <>
      <button type="button">Outside</button>
      {open && (
        <div ref={ref} role="menu">
          <button type="button">Inside</button>
        </div>
      )}
    </>
  )
}

describe("useDismissiblePopup", () => {
  it("closes an open popup with Escape", () => {
    const onClose = vi.fn()
    render(<PopupHarness open={true} onClose={onClose} />)

    fireEvent.keyDown(window, { key: "Escape" })

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it("closes an open popup when pointer input lands outside it", () => {
    const onClose = vi.fn()
    render(<PopupHarness open={true} onClose={onClose} />)

    fireEvent.pointerDown(screen.getByRole("button", { name: "Outside" }))

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it("keeps an open popup when pointer input stays inside it", () => {
    const onClose = vi.fn()
    render(<PopupHarness open={true} onClose={onClose} />)

    fireEvent.pointerDown(screen.getByRole("button", { name: "Inside" }))

    expect(onClose).not.toHaveBeenCalled()
  })

  it("does not install dismissal behavior while closed", () => {
    const onClose = vi.fn()
    render(<PopupHarness open={false} onClose={onClose} />)

    fireEvent.keyDown(window, { key: "Escape" })
    fireEvent.pointerDown(screen.getByRole("button", { name: "Outside" }))

    expect(onClose).not.toHaveBeenCalled()
  })
})
