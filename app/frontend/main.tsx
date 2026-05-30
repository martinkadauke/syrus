import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { App } from "./routes/App"

const root = document.getElementById("syrus-spa-root")

if (root) {
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>
  )
}
