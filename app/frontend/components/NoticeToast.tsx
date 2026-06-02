import { useEffect, type ReactNode } from "react"
import { CloseIcon } from "./CloseIcon"

const AUTO_DISMISS_DELAY_MS = 10_000

export function NoticeToast({ children, message, onDismiss }: { children?: ReactNode; message?: ReactNode | null; onDismiss: () => void }) {
  const content = children ?? message
  useEffect(() => {
    if (!content) return

    const timeout = window.setTimeout(onDismiss, AUTO_DISMISS_DELAY_MS)
    return () => window.clearTimeout(timeout)
  }, [content, onDismiss])

  if (!content) return null

  return (
    <div aria-live="polite" className="fixed right-4 top-20 z-50 max-w-sm sm:right-6" role="status">
      <div className="flex items-start gap-3 rounded border border-gray-200 bg-white px-4 py-3 text-sm text-gray-800 shadow-lg">
        <div className="min-w-0 flex-1">{content}</div>
        <button
          aria-label="Dismiss notification"
          className="-mr-1 inline-flex h-6 w-6 items-center justify-center rounded text-gray-400 hover:bg-gray-100 hover:text-gray-700"
          onClick={onDismiss}
          type="button"
        >
          <CloseIcon />
        </button>
      </div>
    </div>
  )
}
