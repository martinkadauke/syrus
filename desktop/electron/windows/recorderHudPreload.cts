// Preload for the floating recording HUD window (assets/recorderHud.html).
// Bridges the sandboxed HUD page to main: it receives state pushes
// (recorderHud:update), sends button actions back (recorderHud:action —
// stop / discard / the mouse-only pen toggle), and reports the panel's
// content size (recorderHud:resize) so main can fit the window to the text.
// No node/remote access — just these three channels.
import { contextBridge, ipcRenderer } from "electron"

type HudState = Record<string, unknown>

contextBridge.exposeInMainWorld("__recorderHud", {
  action: (kind: "stop" | "discard" | "pen") => ipcRenderer.send("recorderHud:action", kind),
  resize: (size: { width: number; height: number }) => ipcRenderer.send("recorderHud:resize", size),
  onUpdate: (callback: (state: HudState) => void) => {
    ipcRenderer.on("recorderHud:update", (_event, state: HudState) => callback(state))
  }
})
