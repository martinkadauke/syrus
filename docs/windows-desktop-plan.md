# Windows desktop app — design & delivery plan

Status: phase 1 (foundation) implemented on `desktop-app/13-windows`;
phases 2–4 planned. Owner-facing summary of every deliberate decision, so
later phases don't re-litigate them.

## Product contract

Identical to macOS: download one installer, run it, get a tray app with a
guided first-run that either installs a local Dockerized backend or
connects to an existing instance — plus the same web container, inbox,
notifications, hotkey, and auto-updates.

## Decisions

### Installer: NSIS one-click `.exe`, not MSI

electron-updater — the auto-update machinery the mac app already ships —
supports NSIS but **not MSI**. An MSI would freeze every install at its
first version (or force a parallel manual-update story), which breaks the
"backend image pinned per app release" contract that auto-update keeps
honest. So the canonical artifact is the NSIS one-click installer
(`Syrus-Setup-<version>-<arch>.exe`): double-click, zero wizard pages,
per-user install under `%LocalAppData%\Programs\Syrus` (no admin), Start
menu + optional desktop shortcut, silent `/S` flag for fleet deployment.
An additional `msi` target can be added later purely for enterprise GPO
distribution, documented as "no auto-update; IT owns upgrades."

This is the one place we deliberately deviate from the literal ask
("download the .msi installer") — the .exe gives the smoother experience
the ask is actually about: it IS the self-install (no DMG-style
double-click-to-copy dance needed at all) and it keeps auto-update.

### Docker engine recommendation: Docker Desktop first, Podman Desktop offered

OrbStack is macOS-only, so Windows needs its own recommendation. Facts
that drive it:

- Any engine on Windows rides WSL2. `install.sh` (or its PowerShell port)
  talks to a Docker-API socket exposed to Windows.
- **Docker Desktop** exposes `docker.exe` + the named pipe natively,
  `docker compose` included — the compose file works unchanged. License:
  free for small orgs/personal use; paid for large employers.
- **Podman Desktop** is fully open source. `podman compose` drives our
  compose file via podman's Docker-compatible socket; detection is
  slightly different (machine must be started, socket must be enabled).

Recommendation shown to users: Docker Desktop as the default happy path
(most reliable compose semantics), Podman Desktop as the explicitly
supported open-source alternative — mirroring how macOS recommends
OrbStack while supporting Docker Desktop/Colima. Detection order:
`docker.exe` on PATH or Docker Desktop's install dir → podman machine
with docker socket → offer downloads of both.

### Local backend install: PowerShell port, not WSL-bash

`install.sh` assumes bash, Homebrew, `open -a` — none exist on Windows.
Two options were considered:

1. Run install.sh inside WSL (`wsl.exe bash install.sh`) — tempting but
   wrong: it puts Syrus's state inside a WSL distro the user may reset,
   requires a distro to exist (Docker Desktop's special distros don't
   count), and doubles the failure surface.
2. **Port the installer to PowerShell** (`install.ps1`) implementing the
   same machine interface (`--json` progress events, exit codes, `--image`,
   `--target-dir`, `--port`) so `installerDriver.ts` stays engine-agnostic.
   State lives at `%LocalAppData%\Syrus\local\` (compose file, `.env`,
   install log) — the direct analog of `~/.syrus/local/`.

Option 2 is the plan. The compose file and image are identical; only the
bootstrap script differs. The driver contract (JSON events over stdout)
is already covered by CI's machine-interface tests, which the PowerShell
port must pass verbatim (same events, same exit codes).

### Tray: same paradigm, Windows-native details

Electron's `Tray` works on Windows; the existing code already branches
correctly (badged icon instead of macOS title text, taskbar-relative
popover positioning). Windows specifics:

- Icon: dedicated 32×32-optimized `.ico` variant (template images don't
  exist on Windows; use the full-color mark).
- The tray lives in the notification-area overflow by default; first-run
  copy tells users they can drag it out. No dock equivalent — the window
  simply appears in the taskbar when open (`app.dock` calls are already
  darwin-gated).
- Hotkey stays `CommandOrControl+Shift+S` → Ctrl+Shift+S (no conflict
  with Windows 11 snipping, which is Win+Shift+S).

### Windows on ARM

UTM/Parallels users and ARM laptops run Windows 11 ARM64. Electron ships
win32-arm64; the NSIS target builds per-arch. We ship x64 **and** arm64
installers (stable aliases `Syrus-Setup.exe` / `Syrus-Setup-arm64.exe`).
The backend image is already multi-arch (amd64/arm64), so a local install
under an ARM64 Docker Desktop/WSL2 works too.

### Auto-update

electron-updater's NSIS path (`latest.yml` + installer + blockmap on the
same GitHub Releases feed). No zip artifact needed on Windows. Unsigned
builds auto-update fine; SmartScreen friction at first install goes away
once we sign (below).

### Code signing

Phase-4 item: an OV/EV Authenticode cert (or Azure Trusted Signing),
wired through electron-builder's `win.certificateSubjectName`/CSC env in
the release workflow. Until then Windows builds are for testing; the
docs page will mark the download as beta and explain the SmartScreen
"More info → Run anyway" step.

## Phases

1. **Foundation (this branch).** `icon.ico` + generator script; NSIS
   config in electron-builder.yml; platform seams (`titleBarStyle`,
   bash spawns gated); Windows runtime detection returning
   download recommendations (Docker Desktop, Podman Desktop); Welcome
   screen offers connect-mode on Windows and labels local install as
   arriving next; CI builds an unsigned NSIS installer per arch.
2. **Local install.** `install.ps1` with the same machine interface,
   driven by the same installerDriver; WSL2 preflight; engine start
   (`Start-Process` Docker Desktop / `podman machine start`); adopt
   existing installs; port-conflict flow. Release workflow gains a
   `release-windows` job (windows-latest runner) building + publishing
   both arches with stable aliases.
3. **Parity polish.** Windows notification behaviors (toast actions),
   Start-with-Windows login item, per-monitor DPI checks over the tray
   popover, `.ico` badge rendering QA, first-run "pin the tray icon" hint.
4. **Signing + GA.** Authenticode signing in CI, SmartScreen reputation,
   website download buttons out of beta.

## Testing without nested virtualization (Windows 11 on UTM)

UTM on Apple Silicon cannot run WSL2/Docker inside the guest (no nested
virtualization). The test plan splits what runs where:

- **Backend on the Mac host.** `bin/build-local-image && SYRUS_PORT=3000
  bin/compose-up` (or the mac desktop app's own local install). Bind is
  0.0.0.0, so the guest reaches it at the host's IP — with UTM's default
  shared network, `http://<mac-ip>:3000`; UTM emulated VLAN also exposes
  the gateway alias `10.0.2.2`.
- **Windows app in the guest** (arm64 NSIS build): exercise install →
  tray → first-run → **Connect to existing Syrus** → `http://<mac-ip>:3000`
  + desktop token → web container, inbox, notifications, hotkey,
  auto-update (point SYRUS_UPDATE_FEED at a draft release).
- **What this covers:** everything except the local-Docker install path —
  installer UX, tray paradigm, web container, token provisioning,
  update loop, ARM64 build health.
- **Local-install path** is tested in CI (PowerShell installer against
  the machine-interface suite on windows-latest, which does have WSL2)
  plus, eventually, one real x64 Windows box (or a cloud VM like an Azure
  D-series with nested virt) for an end-to-end dress rehearsal.

## Open questions (deliberately deferred)

- Whether the web container should use a custom titlebar on Windows to
  match the mac hiddenInset look, or keep the native frame (phase 3).
- MSI-for-enterprise packaging (post-GA, on demand).
- Winget manifest publication once signing lands.
