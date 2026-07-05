import syrusIconUrl from "../assets/syrusIcon.png"

// Shown in the web-container window when the Syrus backend isn't answering.
// This surface is deliberately inert: the window has no preload bridge (the
// remote web app must never see it), so the main process polls the backend
// and swaps this page back out the moment it responds.
export function BackendStatus() {
  const params = new URLSearchParams(window.location.search)
  const detail = params.get("detail")

  return (
    <div className="flex h-screen flex-col items-center justify-center bg-slate-50 px-10 text-center text-slate-900 antialiased">
      <img src={syrusIconUrl} alt="" className="h-12 w-12 opacity-70" />
      <h1 className="mt-5 text-xl font-semibold">Waiting for Syrus…</h1>
      <p className="mt-2 max-w-sm text-sm leading-relaxed text-slate-600">
        {detail === "remote"
          ? "Your Syrus instance isn't reachable right now. This window reconnects automatically."
          : "Syrus isn't answering yet — it may still be starting. This window reconnects automatically. You can also start or restart it from the Backend menu."}
      </p>
      <p className="mt-6 text-sm text-slate-400" role="status">
        <span
          aria-hidden
          className="mr-2 inline-block h-3 w-3 animate-spin rounded-full border-2 border-slate-400 border-t-transparent align-middle"
        />
        Checking again…
      </p>
    </div>
  )
}
