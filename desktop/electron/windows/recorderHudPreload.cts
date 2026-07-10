// Preload for the floating recording HUD window (assets/recorderHud.html).
// Bridges the sandboxed HUD page to main: it receives state pushes
// (recorderHud:update) and sends button actions back (recorderHud:action).
// No node/remote access — just these two channels.
import { contextBridge, ipcRenderer } from "electron"

type HudState = Record<string, unknown>

contextBridge.exposeInMainWorld("__recorderHud", {
  action: (kind: "stop" | "discard") => ipcRenderer.send("recorderHud:action", kind),
  onUpdate: (callback: (state: HudState) => void) => {
    ipcRenderer.on("recorderHud:update", (_event, state: HudState) => callback(state))
  }
})
