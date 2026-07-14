# frozen_string_literal: true

require "spec_helper"

# The main window is a web container over the (local or remote) Syrus web
# app. Remote content must never see the IPC bridge, external links must
# leave the app, and losing the backend swaps in an inert status page that
# recovers automatically.
RSpec.describe "desktop web-container window" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }

  def read(relative_path)
    File.read(File.join(desktop_root, relative_path), encoding: "UTF-8")
  end

  let(:web_app_window) { read("electron/windows/webAppWindow.ts") }
  let(:main_process) { read("electron/main.ts") }
  let(:renderer_entry) { read("src/main.tsx") }
  let(:backend_status) { read("src/BackendStatus.tsx") }

  it "loads remote content fully isolated, with only the shell-notice preload" do
    expect(web_app_window).to include("contextIsolation: true")
    expect(web_app_window).to include("nodeIntegration: false")
    expect(web_app_window).to include("sandbox: true")
    # The ONLY bridge is the minimal shell-notice preload (window.syrusShell,
    # webAppPreload.cts) — never the tray's preload.cjs, whose credential and
    # filesystem IPC remote content must not see.
    expect(web_app_window).to include("preload: preloadPath")
    expect(main_process).to match(%r{preloadPath: path\.join\(__dirname, "windows", "webAppPreload\.cjs"\)})
    expect(main_process).not_to match(/createWebAppWindow\(\{[\s\S]{0,1200}"preload\.cjs"/)
  end

  it "keeps same-origin navigation in-window and opens everything else externally" do
    expect(web_app_window).to include('window.webContents.on("will-navigate"')
    expect(web_app_window).to include("window.webContents.setWindowOpenHandler")
    expect(web_app_window).to include("decideWindowOpen")
    expect(web_app_window).to include("shell.openExternal")
  end

  it "confines server-side redirects too — will-navigate never fires for a 302" do
    # A same-origin URL that 302s off-origin would otherwise leave a foreign
    # page running in this window with the syrusShell preload attached.
    # will-redirect fires exactly there; preventDefault cancels the whole
    # navigation and off-origin destinations go to the default browser.
    # (main.ts's shell:* sender validation stays as the backstop.)
    redirect_handler = web_app_window[/window\.webContents\.on\("will-redirect"[\s\S]{0,700}/]
    expect(redirect_handler).not_to be_nil
    expect(redirect_handler).to include("if (!isMainFrame)")
    expect(redirect_handler).to include("decideWindowOpen(targetUrl, serverOrigin)")
    expect(redirect_handler).to include("event.preventDefault()")
    expect(redirect_handler).to include("shell.openExternal(targetUrl)")
  end

  it "never allows popups — flows that need a real browser use the syrus_external marker" do
    # POST-carrying popups (form target=_blank) are not special-cased any
    # more: a POST body cannot survive the hand-off to the external browser,
    # so such flows (the GitHub App manifest) run through a same-origin GET
    # bounce page marked syrus_external=1, which the policy routes to the
    # default browser where the user has real logins.
    window_open_policy = read("electron/windows/windowOpenPolicy.ts")
    expect(window_open_policy).to include('searchParams.get("syrus_external") === "1"')
    expect(web_app_window).not_to include('action: "allow"')
    expect(web_app_window).not_to include("postBody")
    expect(web_app_window).not_to include("did-create-window")
  end

  it "marks the web container's user agent so the web app can detect the shell" do
    expect(web_app_window).to include("SyrusDesktop/")
    expect(web_app_window).to include("setUserAgent")
    # The app build rides a second UA token (from the staged manifest) so the
    # web UI's BuildBadge can show which build hosts it. Release builds
    # announce the release version, dev builds the git sha — one token,
    # version-or-sha ("0.0.0" is the dev placeholder, never a release).
    expect(web_app_window).to include("SyrusDesktopBuild/")
    expect(main_process).to include(
      'buildSha: (manifest?.appVersion && manifest.appVersion !== "0.0.0" ? manifest.appVersion : manifest?.appBuild) ?? null'
    )
    # A third token carries the app's build time for the badge's hover
    # tooltip, encoded ISO-8601 BASIC (20260707T143200Z) because colons are
    # not valid in UA product-version tokens — desktopBuiltAt() decodes it.
    expect(web_app_window).to include("SyrusDesktopBuiltAt/")
    expect(web_app_window).to include('.toISOString().slice(0, 19).replace(/[-:]/g, "")')
    # A fourth token flags the TEST channel so the SPA's TestChannelBadge /
    # TestChannelDot light up. Pin the PRODUCER string here: isDesktopTestChannel
    # (and its component tests) match /\bSyrusDesktopChannel\/test\b/, so a typo
    # in this emitter would silently disable the in-app TEST indicator while the
    # consumer tests keep passing on their own hardcoded UA.
    expect(web_app_window).to include(
      'currentChannel() === "test" ? " SyrusDesktopChannel/test" : ""'
    )
    expect(main_process).to include("builtAt: manifest?.builtAt ?? null")
    # stage-backend-assets stamps the timestamp the token is derived from.
    # Dev builds stamp the wall clock (staging time IS the build moment);
    # release builds derive it from HEAD's committer date — the same source
    # release.yml / bin/publish-image bake into the backend image as
    # SYRUS_BUILT_AT — normalized to the identical second-precision UTC
    # ISO-8601 form, so the BuildBadge's app and backend tooltips show the
    # IDENTICAL instant on a release.
    stage_script = read("scripts/stage-backend-assets.mjs")
    expect(stage_script).to include("if (!isReleaseBuild) return new Date().toISOString()")
    expect(stage_script).to include('execSync("git show -s --format=%ct HEAD"')
    expect(stage_script).to include('new Date(Number(epochSeconds) * 1000).toISOString().replace(/\.\d{3}Z$/, "Z")')
    expect(stage_script).to include("appVersion: version, appBuild, builtAt")
  end

  it "exposes the context-menu essentials to the left-click popover" do
    expect(main_process).to include('ipcMain.handle("open-syrus"')
    expect(main_process).to include('ipcMain.handle("quit-app"')
    preload = read("electron/preload.cts")
    expect(preload).to include("openSyrusWindow")
    expect(preload).to include("quitApp")
    tray_app = read("src/App.tsx")
    expect(tray_app).to include("TrayActionsBar")
  end

  it "falls back to the status page only for real main-frame failures of the server URL" do
    expect(web_app_window).to include('"did-fail-load"')
    # ERR_ABORTED (-3) is benign (superseded navigation / download) and must
    # not yank a healthy app to the status page.
    expect(web_app_window).to include("if (errorCode === -3 || !isMainFrame || !validatedURL.startsWith(serverOrigin))")
  end

  it "denies renderer-initiated file: navigations" do
    # The old guard carried a file: exemption; the policy must deny all
    # non-web protocols.
    window_open_policy = read("electron/windows/windowOpenPolicy.ts")
    expect(web_app_window).not_to include('target.protocol !== "file:"')
    expect(window_open_policy).to match(/if \(!\["http:", "https:"\]\.includes\(target\.protocol\)\) \{\s*return "deny"/)
  end

  it "gates startup on the single-instance lock so the losing instance runs nothing" do
    expect(main_process).to include("const hasSingleInstanceLock = app.requestSingleInstanceLock(ownInstanceIdentity())")
    when_ready = main_process[/app\.whenReady\(\)\.then\(async \(\) => \{[\s\S]{0,200}/]
    expect(when_ready).to include("if (!hasSingleInstanceLock)")
  end

  it "offers takeover when a different version or bundle launches against a running instance" do
    # Field lesson: a stale copy running off a mounted DMG silently swallowed
    # every newer launch. The launching instance identifies itself via the
    # lock's additionalData; the running instance offers Switch/Keep, and on
    # Switch releases the lock BEFORE launching the new copy (or the new copy
    # loses the lock race against the dying instance — the original trap).
    expect(main_process).to include("decideOnSecondInstance(own, incoming)")
    handler = main_process[/app\.on\("second-instance"[\s\S]{0,2600}/]
    expect(handler).to include("takeoverPrompt(own, incoming")
    expect(handler.index("app.releaseSingleInstanceLock()")).to be < handler.index("launchInstalledCopy(")
    expect(handler).to include("void openSyrus()")
    # While the self-install gate's dialog is pending, a second instance
    # (re-double-clicked DMG) must only re-surface the dialog — never route
    # to openSyrus and open a window from the mounted image.
    guard = handler[/if \(selfInstallGateActive\) \{[\s\S]{0,200}?\n  \}/]
    expect(guard).to include("app.focus({ steal: true })")
    expect(guard).to include("return")
    expect(guard).not_to include("openSyrus")
    expect(handler.index("if (selfInstallGateActive)")).to be < handler.index("decideOnSecondInstance")
  end

  it "recovers by polling /up from the main process and reloading" do
    expect(main_process).to include("startBackendRecoveryPolling")
    expect(main_process).to include("${serverUrl}/up")
    expect(main_process).to include("await webAppWindow?.loadServerUrl()")
  end

  it "keeps the fallback surface inert — no IPC bridge usage" do
    expect(renderer_entry).to include('view === "backend-status"')
    expect(backend_status).not_to include("window.syrusDesktop")
  end

  it "enforces a single running instance that focuses the existing one" do
    expect(main_process).to include("app.requestSingleInstanceLock(ownInstanceIdentity())")
    expect(main_process).to include('app.on("second-instance"')
  end

  it "self-installs into Applications before opening any window" do
    # The DMG's double-click contract: running from the mounted image (or
    # Downloads) installs the bundle into Applications — /Applications when
    # writable without admin rights, ~/Applications otherwise — launches the
    # copy, and quits. No drag target. A fresh install stays silent, but an
    # existing install is only replaced after a Replace/Keep-Existing prompt
    # that names both versions. The lock is released before each launch so
    # the launched copy doesn't lose the single-instance race against this
    # instance.
    when_ready = main_process[/app\.whenReady\(\)\.then\(async \(\) => \{[\s\S]*/]
    expect(when_ready).to include("shouldSelfInstall(")
    expect(when_ready).to include("resolveInstallTarget(")
    expect(when_ready).to include("installedBundleVersion(")
    expect(when_ready).to include("installBundle(")

    # A fresh install stays silent: the replace prompt exists ONLY inside the
    # existing-install gate, and it precedes any copying.
    existing_gate = when_ready[/if \(target\.existingInstall\) \{[\s\S]*?\n {6}\}\n/]
    expect(existing_gate).to include("replacePrompt(")
    expect(existing_gate).to include("installDecisionForResponse(")
    expect(existing_gate).not_to include("installBundle(")
    expect(when_ready.scan("replacePrompt(").length).to eq(1)
    expect(when_ready.index("replacePrompt(")).to be < when_ready.index("installBundle(")

    # Declining really does prevent the copy: the decline branch quits and
    # returns without ever reaching installBundle.
    decline_branch = when_ready[/if \(installDecisionForResponse\(prompt, choice\.response\) === "launch-existing"\) \{[\s\S]*?\n {8}\}\n/]
    expect(decline_branch).to include("app.quit()")
    expect(decline_branch).to include("return")
    expect(decline_branch).not_to include("installBundle(")

    # BOTH hand-over paths (keep-existing and post-install) release the lock
    # BEFORE their launch, or the launched copy loses the single-instance
    # race against this dying instance.
    releases = when_ready.enum_for(:scan, /app\.releaseSingleInstanceLock\(\)/).map { Regexp.last_match.begin(0) }
    launches = when_ready.enum_for(:scan, /await launchInstalledCopy\(/).map { Regexp.last_match.begin(0) }
    expect(releases.length).to eq(2)
    expect(launches.length).to eq(2)
    launches.each_with_index do |launch, i|
      own_release = releases.select { |release| release < launch && (i.zero? || release > launches[i - 1]) }
      expect(own_release).not_to be_empty
    end
    expect(when_ready.index("launchInstalledCopy(")).to be < when_ready.index("createMenu()")

    # No DMG session, ever — and no silent-nothing endings. The outer catch
    # distinguishes a failed COPY (installFailedPrompt, manual drag) from a
    # failed LAUNCH after a successful install (launchFailedPrompt, open from
    # Applications), logs the cause, and quits. The keep-existing launch
    # failure gets its own dialog too. Every dialog in the gate steals focus
    # first — the dock is hidden, so a parentless dialog can otherwise sit
    # behind Finder while we hold the single-instance lock.
    outer_catch = when_ready[/\n {4}\} catch \(error\) \{[\s\S]*?app\.quit\(\)/]
    expect(outer_catch).to include("? launchFailedPrompt(")
    expect(outer_catch).to include(": installFailedPrompt(")
    expect(outer_catch).to include("console.warn(")
    inner_catch = when_ready[/\n {10}\} catch \(error\) \{[\s\S]*?\n {10}\}/]
    expect(inner_catch).to include("launchFailedPrompt(")
    expect(inner_catch).to include("console.warn(")
    expect(when_ready.scan("app.focus({ steal: true })").length).to be >= 3
    expect(when_ready).not_to include("Keep running from the current location")
    expect(when_ready).not_to include("launchInstalledCopy(target.path).catch")

    self_install = read("electron/selfInstall.ts")
    expect(self_install).to include("/usr/bin/ditto")
    # /Applications is the preferred target; ~/Applications the admin-free
    # fallback; an existing install is replaced where it can actually be
    # replaced (a non-writable /Applications copy is never targeted).
    expect(self_install).to include('export const SYSTEM_APPLICATIONS = "/Applications"')
    expect(self_install).to match(%r{path\.join\(homeDir, "Applications"\)})
    expect(self_install).to include("if (systemExists && systemWritable) {")
    expect(self_install).to include("systemWritable ? systemPath : userPath")
    # The copy is staged and swapped — never destroy-then-copy, so a failed
    # install can never leave zero runnable copies where one existed.
    expect(self_install).to include(".installing-")
    expect(self_install).to include(".previous-")
    # A 0.0.0 dev build must read as unknown — never "newer", never a silent
    # downgrade of a versioned install.
    expect(self_install).to include('export const UNKNOWN_VERSION = "0.0.0"')
    expect(self_install).to include("CFBundleShortVersionString")
  end

  it "shows the dock icon only while a real window is open" do
    expect(main_process).to include("const updateDockVisibility = () => {")
    expect(main_process).to include("app.dock?.show()")
    expect(main_process).to include("app.dock?.hide()")
  end

  it "opens the web window (not the browser) from launch, activate, and the tray" do
    expect(main_process).to include("await showWebAppWindow()")
    expect(main_process).to include("void openSyrus()")
    expect(main_process).not_to include("openSyrusInBrowser")
  end

  it "persists and restores the window bounds" do
    expect(main_process).to include('store.get("webAppWindowBounds", null)')
    expect(main_process).to include('store.set("webAppWindowBounds", bounds)')
  end
end
