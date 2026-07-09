# frozen_string_literal: true

require "spec_helper"

# The red-pen annotation overlay for the walkthrough recorder: a frameless,
# transparent, always-on-top Electron window spanning EVERY display. The
# recorder's full-screen getDisplayMedia captures it INCIDENTALLY, so marks the
# user draws are burned into the recorded video with no change to the capture
# pipeline.
#
# Interaction model: PRESS-TO-ARM, AUTO-RELEASE (not a persistent toggle).
# Tapping the global shortcut (CommandOrControl+Shift+A) arms draw mode; the
# overlay AUTO-RELEASES back to click-through once the pointer pauses
# (ARM_IDLE_RELEASE_MS idle with no stroke in progress), so the app under test
# stays interactive except while the user is actively annotating. Esc and a
# second tap release immediately; a hard MAX_ARMED_MS cap force-releases
# regardless. No native key hook and no macOS accessibility permission — a true
# modifier-HOLD would need both (uiohook-napi + Accessibility), which this app
# deliberately avoids; auto-release delivers the same click-through benefit for
# free and leaves the native hold as a future opt-in.
#
# The overriding safety rules are: the overlay must NEVER steal keyboard focus
# when armed, must NEVER stay stuck capturing the screen (idle auto-release +
# hard cap + instant release on disable all guarantee this), and must NEVER
# advertise a shortcut it did not actually register.
#
# The bridges are stringly typed (see ipc_channel_parity_spec.rb) and the
# overlay module talks to Electron APIs that can't run under vitest, so this
# static scan pins the window flags, focus discipline, shortcut lifecycle, IPC
# wiring, teardown-on-crash/reload, and the fade constants the standalone
# overlay HTML mirrors from the tested TS module.
RSpec.describe "desktop annotation overlay" do
  let(:repo_root) { File.expand_path("../..", __dir__) }
  let(:desktop_root) { File.join(repo_root, "desktop") }

  def read(relative_path)
    File.read(File.join(desktop_root, relative_path), encoding: "UTF-8")
  end

  let(:overlay) { read("electron/windows/annotationOverlay.ts") }
  let(:main) { read("electron/main.ts") }
  let(:preload) { read("electron/windows/webAppPreload.cts") }
  let(:overlay_html) { read("assets/annotationOverlay.html") }
  let(:fade_module) { read("src/annotationFade.ts") }
  let(:builder_config) { read("electron-builder.yml") }

  describe "the overlay window" do
    it "is a frameless, transparent, always-on-top, click-through-by-default surface" do
      expect(overlay).to include("frame: false")
      expect(overlay).to include("transparent: true")
      expect(overlay).to include("hasShadow: false")
      expect(overlay).to include("skipTaskbar: true")
      expect(overlay).to include("alwaysOnTop: true")
      # Highest practical level so it floats above other apps.
      expect(overlay).to include('setAlwaysOnTop(true, "screen-saver")')
      # Visible over fullscreen spaces on macOS.
      expect(overlay).to include("setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })")
      # Starts click-through: never blocks the app under test until draw mode.
      expect(overlay).to include("setIgnoreMouseEvents(true, { forward: true })")
      # No remote content — a local sandboxed canvas page.
      expect(overlay).to match(/contextIsolation: true[\s\S]{0,120}sandbox: true/)
    end

    it "is created NON-ACTIVATING so arming it never steals the narrator's focus" do
      # Created hidden + non-focusable, then shown WITHOUT activating. enable()
      # must not move focus off the app the narrator is demonstrating.
      expect(overlay).to include("show: false")
      expect(overlay).to include("focusable: false")
      expect(overlay).to include("showInactive()")
      # The old bug created a focusable window on enable(); guard the regression.
      expect(overlay).not_to include("focusable: true")
      # enable() itself must not grab focus (focus is a draw-mode-only action).
      enable = overlay[/const enable[\s\S]{0,3600}/]
      expect(enable).not_to include("overlay.focus()")
    end

    it "spans the union of every display, not just the primary one" do
      # Multi-monitor fix: cover the whole virtual desktop so drawing shows up
      # on whichever monitor is shared. The primary-only MVP is gone.
      expect(overlay).to include("screen.getAllDisplays()")
      expect(overlay).not_to include("getPrimaryDisplay()")
      # Union bounding box drives the window geometry.
      expect(overlay).to include("const virtualDesktopBounds")
      expect(overlay).to match(/Math\.min\([\s\S]{0,120}bounds\.x/)
      expect(overlay).to match(/Math\.max\([\s\S]{0,160}bounds\.x \+ d\.bounds\.width/)
    end

    it "grants focus ONLY in draw mode and drops it the instant draw mode ends" do
      set_armed = overlay[/const setArmed[\s\S]{0,2000}/]
      # Armed → capture (ignore=false) + take focus so the canvas + Esc work.
      expect(set_armed).to include("setIgnoreMouseEvents(!next, { forward: true })")
      expect(set_armed).to match(/setFocusable\(true\)[\s\S]{0,80}focus\(\)/)
      # Released → blur + drop focusability so no keystroke is ever swallowed.
      expect(set_armed).to match(/blur\(\)[\s\S]{0,80}setFocusable\(false\)/)
      # Mirror the transition to the web HUD.
      expect(set_armed).to include("onModeChanged(next)")
    end

    it "leaves draw mode on Escape (which draw-mode focus now makes reachable)" do
      expect(overlay).to include("before-input-event")
      expect(overlay).to match(/input\.key === "Escape"[\s\S]{0,80}setArmed\(false\)/)
    end
  end

  describe "the draw-mode global shortcut" do
    it "is a normal accelerator, registered on enable and unregistered on disable" do
      expect(overlay).to include('export const ANNOTATION_SHORTCUT = "CommandOrControl+Shift+A"')
      # enable() registers the arm/release handler...
      enable = overlay[/const enable[\s\S]{0,3600}/]
      expect(enable).to include("globalShortcut.register(ANNOTATION_SHORTCUT, toggleArm)")
      # ...disable() unregisters it.
      disable = overlay[/const disable[\s\S]{0,1800}/]
      expect(disable).to include("globalShortcut.unregister(ANNOTATION_SHORTCUT)")
    end

    it "taps to arm and taps again to release (press-to-arm, not a sticky toggle)" do
      # The accelerator flips armed state: tap arms, tap again releases. The
      # NEW behavior is that draw mode also auto-releases on idle, so the tap is
      # a shortcut in, not a persistent on/off the user must remember to undo.
      expect(overlay).to include("const toggleArm = () => setArmed(!armed)")
    end

    it "returns false (not true) when the accelerator is already owned" do
      # register() returns false without throwing when the accelerator is taken.
      # A registered-but-false shortcut would advertise a dead shortcut, so
      # enable() must tear the overlay down and report unavailable.
      enable = overlay[/const enable[\s\S]{0,3600}/]
      expect(enable).to match(/if \(!globalShortcut\.register\(ANNOTATION_SHORTCUT, toggleArm\)\) \{[\s\S]{0,120}destroyOverlayNow\(\)[\s\S]{0,40}return false/)
    end

    it "never lets overlay creation crash the recording — enable() try/catch returns false" do
      # Lazy match, length-independent: enable() has a try that returns true and
      # a catch that returns false (create failure → unavailable, not a crash).
      expect(overlay).to match(/const enable[\s\S]*?try \{[\s\S]*?return true[\s\S]*?\} catch \{[\s\S]*?return false/)
      # A failed create/registration tears down the partial window + shortcut
      # through the shared destroy helper.
      expect(overlay).to match(/const destroyOverlayNow[\s\S]{0,220}overlay!\.destroy\(\)/)
    end

    it "gives enable() TRUE only when the overlay exists AND the shortcut registered" do
      # The two failure exits (create throw, register false) both return false;
      # the single success path returns true only after showInactive().
      expect(overlay).to match(/showInactive\(\)[\s\S]{0,60}return true/)
    end
  end

  describe "disable(): instant input release, graceful fade, real teardown" do
    it "stops capturing input INSTANTLY so it can never stay stuck over the screen" do
      disable = overlay[/const disable[\s\S]{0,1800}/]
      # Click-through + non-focusable immediately, before any deferred destroy.
      expect(disable).to include("setIgnoreMouseEvents(true, { forward: true })")
      expect(disable).to match(/blur\(\)[\s\S]{0,80}setFocusable\(false\)/)
      # The auto-release watchers (idle poll + hard cap) are killed on disable so
      # neither can fire after teardown.
      expect(disable).to include("stopArmWatch()")
    end

    it "wires the previously-dead clear() so lingering marks fade on stop" do
      disable = overlay[/const disable[\s\S]{0,1800}/]
      # clear() is invoked over the executeJavaScript control surface on stop.
      expect(disable).to include("__syrusAnnotation.clear()")
      # The overlay HTML still defines clear() as that control surface.
      expect(overlay_html).to match(/clear: function \(\)/)
    end

    it "destroys the overlay so it never outlives a recording, and is idempotent" do
      # The shared teardown helper destroys + nulls the window and kills timers...
      destroy = overlay[/const destroyOverlayNow[\s\S]{0,320}/]
      expect(destroy).to include("overlay!.destroy()")
      expect(destroy).to include("overlay = null")
      expect(destroy).to include("stopArmWatch()")
      # ...and disable() schedules it after the fade window (single timer).
      disable = overlay[/const disable[\s\S]{0,1800}/]
      expect(disable).to match(/if \(!teardownTimer\)[\s\S]{0,120}setTimeout\(destroyOverlayNow/)
      # Calling disable() when already down is a safe no-op.
      expect(disable).to include("if (!overlayAlive())")
    end

    it "re-enabling before the fade completes finishes the pending teardown first" do
      enable = overlay[/const enable[\s\S]{0,400}/]
      expect(enable).to match(/if \(teardownTimer\)[\s\S]{0,80}destroyOverlayNow\(\)/)
    end
  end

  describe "press-to-arm / auto-release draw mode" do
    it "mirrors the tested idle/cap timing constants from src/annotationFade.ts" do
      # The tested source of truth (desktop/src/annotationFade.ts).
      expect(fade_module).to include("export const ARM_IDLE_RELEASE_MS = 1200")
      expect(fade_module).to include("export const ARM_POLL_MS = 200")
      expect(fade_module).to include("export const MAX_ARMED_MS = 15_000")
      # The overlay module can't import across the electron/src rootDir split, so
      # it re-declares the same numbers as local literals — pin them together so
      # a drift can't silently change the feel of one and not the other.
      expect(overlay).to include("const ARM_IDLE_RELEASE_MS = 1200")
      expect(overlay).to include("const ARM_POLL_MS = 200")
      expect(overlay).to include("const MAX_ARMED_MS = 15000")
    end

    it "arms/releases through a single setArmed that flips input capture + focus" do
      # setArmed is the one place draw mode transitions: capture toggles with the
      # armed flag, and it is idempotent per state.
      set_armed = overlay[/const setArmed[\s\S]{0,2000}/]
      expect(set_armed).to include("next === armed")
      expect(set_armed).to include("setIgnoreMouseEvents(!next, { forward: true })")
      # Arming starts the auto-release watchers; releasing stops them. The arm
      # branch (startArmWatch) precedes the release branch (stopArmWatch).
      expect(set_armed).to include("startArmWatch()")
      expect(set_armed).to include("stopArmWatch()")
      expect(set_armed.index("startArmWatch()")).to be < set_armed.index("stopArmWatch()")
    end

    it "auto-releases when the pointer pauses (idle poll), never mid-stroke" do
      # A poll samples the renderer's idle snapshot on an interval while armed and
      # releases once the pointer has been quiet for the whole idle window with
      # NO stroke in progress. A mid-stroke pointer (snap.active) is never cut off.
      poll = overlay[/const pollIdle[\s\S]{0,700}/]
      expect(poll).to include("__syrusAnnotation.idleSnapshot()")
      expect(poll).to match(/!snap\.active && \(snap\.idleMs \?\? 0\) >= ARM_IDLE_RELEASE_MS/)
      expect(poll).to include("setArmed(false)")
      # The watcher runs the poll on ARM_POLL_MS.
      expect(overlay).to include("setInterval(pollIdle, ARM_POLL_MS)")
    end

    it "ignores a stale idle snapshot from a previous arm session (generation guard)" do
      # A release→re-arm while a poll's renderer round-trip is in flight must not
      # let the stale reply auto-release the freshly re-armed session. Each poll
      # captures armGeneration and the continuation bails when it no longer matches.
      expect(overlay).to include("armGeneration += 1")
      poll = overlay[/const pollIdle[\s\S]{0,700}/]
      expect(poll).to include("const generation = armGeneration")
      expect(poll).to match(/armGeneration !== generation/)
    end

    it "force-releases at the hard max-armed cap so it can never get stuck armed" do
      # Independent of activity: after MAX_ARMED_MS the overlay releases no matter
      # what, even if the idle poll wedges or the renderer stops reporting.
      start = overlay[/const startArmWatch[\s\S]{0,400}/]
      expect(start).to match(/setTimeout\(\(\) => setArmed\(false\), MAX_ARMED_MS\)/)
    end

    it "kills both auto-release watchers on every release / teardown path" do
      # stopArmWatch clears the idle poll AND the max-armed cap; it must run on
      # release (setArmed false), disable, destroy, and window close so no stray
      # timer outlives draw mode.
      stop = overlay[/const stopArmWatch[\s\S]{0,320}/]
      expect(stop).to include("clearInterval(idlePollTimer)")
      expect(stop).to include("clearTimeout(maxArmedTimer)")
      # The window's own `closed` handler also drops the watchers.
      closed = overlay[/overlay\.on\("closed"[\s\S]{0,160}/]
      expect(closed).to include("stopArmWatch()")
    end

    it "exposes the renderer idle snapshot the poll reads and resets it on arm" do
      # The overlay HTML tracks the last pointer activity and reports a read-only
      # snapshot { active, idleMs } that the main process polls.
      expect(overlay_html).to include("var lastPointerAt")
      expect(overlay_html).to match(/idleSnapshot: function \(\)/)
      expect(overlay_html).to include("active: active != null, idleMs: performance.now() - lastPointerAt")
      # Arming resets the idle clock (fresh full idle window); releasing ends the
      # in-flight stroke so it fades.
      set_armed = overlay_html[/setArmed: function \(armed\)[\s\S]{0,220}/]
      expect(set_armed).to include("noteActivity()")
      expect(set_armed).to include("endStroke()")
      # Any pointer activity (down/move/up) refreshes the idle clock so an active
      # user isn't dropped to click-through mid-gesture.
      expect(overlay_html).to include("function noteActivity()")
    end
  end

  describe "the main-process wiring" do
    it "lazily builds the controller with the packaged overlay HTML and a HUD bridge" do
      expect(main).to include('import { createAnnotationController, type AnnotationController } from "./windows/annotationOverlay.js"')
      factory = main[/const ensureAnnotationController[\s\S]{0,700}/]
      # HTML ships in assets/ (electron-builder assets/**/* glob) under getAppPath().
      expect(factory).to include('path.join(app.getAppPath(), "assets", "annotationOverlay.html")')
      # Draw-mode transitions reach the web recorder's HUD.
      expect(factory).to include('webAppWindow?.window.webContents.send("annotation:mode-changed", drawing)')
    end

    it "guards annotation:enable / annotation:disable with the same sender validation as shell:*" do
      %w[annotation:enable annotation:disable].each do |channel|
        handler = main[/ipcMain\.handle\("#{Regexp.escape(channel)}", \(event\) => \{[\s\S]{0,300}/]
        expect(handler).to include("if (!shellSenderAllowed(event, \"#{channel}\"))"),
          "#{channel} must validate the sender first"
      end
      # enable spins the controller up; disable tears it down.
      enable = main[/ipcMain\.handle\("annotation:enable"[\s\S]{0,700}/]
      expect(enable).to include("ensureAnnotationController().enable()")
      disable = main[/ipcMain\.handle\("annotation:disable"[\s\S]{0,300}/]
      expect(disable).to include("annotationController?.disable()")
    end

    it "PROPAGATES enable()'s boolean back through the IPC channel" do
      # The renderer needs the real availability, not a discarded value: return
      # enable()'s boolean, and reject a disallowed sender as false (unavailable).
      enable = main[/ipcMain\.handle\("annotation:enable"[\s\S]{0,700}/]
      expect(enable).to include("return ensureAnnotationController().enable()")
      expect(enable).to match(/shellSenderAllowed[\s\S]{0,60}return false/)
    end

    it "tears the overlay down when the app window closes and when the app quits" do
      # Closing the web window mid-recording can't run the renderer's disable.
      on_closed = main[/onClosed: \(\) => \{[\s\S]{0,240}webAppWindow = null[\s\S]{0,240}/]
      expect(on_closed).to include("annotationController?.disable()")
      # And a transparent always-on-top window must never survive quit.
      before_quit = main[/app\.on\("before-quit"[\s\S]{0,500}/]
      expect(before_quit).to include("annotationController?.disable()")
    end

    it "tears the overlay down on a renderer crash or a full main-frame reload/navigation" do
      # A Cmd+R reload or a render-process crash reuses the SAME webContents
      # WITHOUT running the React unmount's annotation:disable — an overlay left
      # in draw mode would keep capturing the whole screen. Disable on both.
      gone = main[/webContents\.on\("render-process-gone"[\s\S]{0,120}/]
      expect(gone).to include("annotationController?.disable()")
      nav = main[/webContents\.on\("did-start-navigation"[\s\S]{0,700}/]
      # Only full (non-same-document) main-frame navigations tear down; in-place
      # SPA route changes are left to the React unmount.
      expect(nav).to include("if (isMainFrame && !isInPlace)")
      expect(nav).to include("annotationController?.disable()")
    end
  end

  describe "the preload bridge" do
    it "exposes window.syrusShell.annotation as the web app's feature gate" do
      annotation = preload[/annotation: \{[\s\S]{0,900}/]
      # available:true is the desktop-only STATIC signal — a plain browser has none.
      expect(annotation).to include("available: true")
      # enable() now resolves the runtime boolean the recorder gates its HUD on.
      expect(annotation).to include('enable: () => ipcRenderer.invoke("annotation:enable") as Promise<boolean>')
      expect(annotation).to include('disable: () => ipcRenderer.invoke("annotation:disable")')
      # onModeChanged subscribes + returns an unsubscribe, mirroring onStateChanged.
      expect(annotation).to include('ipcRenderer.on("annotation:mode-changed", listener)')
      expect(annotation).to include('ipcRenderer.removeListener("annotation:mode-changed", listener)')
      # Still exactly one exposeInMainWorld — annotation nests inside syrusShell.
      expect(preload.scan("exposeInMainWorld").length).to eq(1)
    end
  end

  describe "the overlay canvas + shared fade constants" do
    it "renders a self-contained pointer-driven red-pen canvas" do
      expect(overlay_html).to include('<canvas id="pen">')
      expect(overlay_html).to include('addEventListener("pointerdown"')
      expect(overlay_html).to include('addEventListener("pointermove"')
      # Main-process control surface (executeJavaScript target).
      expect(overlay_html).to include("window.__syrusAnnotation")
      # A strict CSP: no remote anything, only the inline canvas script.
      expect(overlay_html).to include("Content-Security-Policy")
    end

    it "mirrors the tested fade constants from src/annotationFade.ts" do
      # The tested source of truth.
      expect(fade_module).to include("export function strokeAlpha(")
      expect(fade_module).to include("export const FADE_DURATION_MS = 2500")
      expect(fade_module).to include("export const STROKE_WIDTH = 6")
      # The standalone HTML re-implements the same numbers (it can't import at
      # runtime) — a drift here means the video looks different from the tests.
      expect(overlay_html).to include("FADE_DURATION_MS = 2500")
      expect(overlay_html).to include("STROKE_WIDTH = 6")
      # The overlay module's graceful-teardown delay uses the same fade window,
      # so the destroy fires only after marks have fully faded.
      expect(overlay).to include("const FADE_DURATION_MS = 2500")
    end
  end

  it "ships the overlay HTML in the packaged app (electron-builder assets glob)" do
    expect(File.exist?(File.join(desktop_root, "assets", "annotationOverlay.html"))).to be(true)
    # The top-level files list bundles assets/**/*, which app.getAppPath()
    # resolves in both dev and the packaged asar.
    expect(builder_config).to match(/files:\s*(?:\n\s*-[^\n]*)*\n\s*-\s*assets\/\*\*\/\*/)
  end
end
