import { useMutation } from "@tanstack/react-query"
import type { ChangeEvent, FormEvent } from "react"
import { useState } from "react"
import { ApiError } from "../api/client"
import { createBugReport } from "../api/bugReports"

export function BugReportButton({ context }: { context: string }) {
  const [open, setOpen] = useState(false)
  const [title, setTitle] = useState("")
  const [description, setDescription] = useState("")
  const [screenshot, setScreenshot] = useState<File | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const bugReport = useMutation({
    mutationFn: () => createBugReport({ title, description, screenshot }),
    onSuccess: (payload) => {
      setOpen(false)
      setNotice(payload.message || "Bug report queued.")
      setTitle("")
      setDescription("")
      setScreenshot(null)
    }
  })

  function openDialog() {
    bugReport.reset()
    setTitle(`${context} bug`)
    setDescription("")
    setScreenshot(null)
    setNotice(null)
    setOpen(true)
  }

  function closeDialog() {
    bugReport.reset()
    setOpen(false)
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    bugReport.mutate()
  }

  function updateScreenshot(event: ChangeEvent<HTMLInputElement>) {
    setScreenshot(event.target.files?.[0] || null)
  }

  return (
    <>
      {notice ? (
        <div className="fixed bottom-20 left-4 z-40 max-w-sm rounded border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm font-medium text-emerald-800 shadow" role="status">
          {notice}
        </div>
      ) : null}
      <button
        aria-label="Report a bug"
        className="fixed bottom-4 left-4 z-40 flex h-12 w-12 items-center justify-center rounded-full bg-rose-600 text-xl font-semibold text-white shadow-lg shadow-rose-900/20 hover:bg-rose-500 focus:outline-none focus:ring-2 focus:ring-rose-500 focus:ring-offset-2"
        onClick={openDialog}
        title="Report a bug"
        type="button"
      >
        !
      </button>
      {open ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <section aria-labelledby="bug-report-title" aria-modal="true" className="max-h-[calc(100vh-2rem)] w-full max-w-2xl overflow-y-auto rounded-lg bg-white shadow-xl" role="dialog">
            <form className="space-y-5 p-5 sm:p-6" onSubmit={submit}>
              <div className="flex items-start justify-between gap-4">
                <h2 className="text-lg font-semibold text-gray-900" id="bug-report-title">Report a bug</h2>
                <button
                  aria-label="Close"
                  className="rounded-md p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-700"
                  onClick={closeDialog}
                  type="button"
                >
                  x
                </button>
              </div>

              <label className="block text-sm font-medium text-gray-700">
                Title
                <input
                  className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  onChange={(event) => setTitle(event.target.value)}
                  required
                  type="text"
                  value={title}
                />
              </label>

              <label className="block text-sm font-medium text-gray-700">
                Description
                <textarea
                  className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  onChange={(event) => setDescription(event.target.value)}
                  rows={5}
                  value={description}
                />
              </label>

              <label className="block text-sm font-medium text-gray-700">
                Screenshot
                <input accept="image/png" className="mt-1 block w-full text-sm text-gray-700" onChange={updateScreenshot} type="file" />
              </label>

              {bugReport.isError ? (
                <p className="rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700" role="alert">
                  {errorMessage(bugReport.error, "Bug report could not be queued.")}
                </p>
              ) : null}

              <div className="flex justify-end gap-2 border-t border-gray-100 pt-4">
                <button className="rounded-md border border-gray-300 px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-50" onClick={closeDialog} type="button">
                  Cancel
                </button>
                <button className="rounded-md bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-500 disabled:bg-blue-300" disabled={bugReport.isPending} type="submit">
                  {bugReport.isPending ? "Creating..." : "Create Job"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
    </>
  )
}

function errorMessage(error: Error, fallback: string) {
  return error instanceof ApiError ? error.message : fallback
}
