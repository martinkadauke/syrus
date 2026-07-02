import React from "react"
import { createRoot } from "react-dom/client"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { App } from "./App"
import { OnboardingApp } from "./onboarding/OnboardingApp"
import "./styles.css"

const root = document.getElementById("root")

if (!root) {
  throw new Error("Missing root element")
}

// Windows pick their surface via ?view=. Onboarding is a self-contained
// first-run flow — no server state, so no query client.
const view = new URLSearchParams(window.location.search).get("view")

const surface =
  view === "onboarding" ? (
    <OnboardingApp />
  ) : (
    <QueryClientProvider client={new QueryClient()}>
      <App />
    </QueryClientProvider>
  )

createRoot(root).render(<React.StrictMode>{surface}</React.StrictMode>)
