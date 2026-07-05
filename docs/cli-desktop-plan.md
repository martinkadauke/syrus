# Syrus CLI × desktop app — why, how, and what ships when

Status: phases 1 (bundle + one-click install + auto-login) and 2 (the
Claude Code skill, plus the one-time post-setup install step) implemented
on `desktop-app/11-e2e-polish`; phase 3 planned.

## Why a desktop user wants the CLI at all

1. **The tray's Checkout button literally runs it.** `syrus checkout
   JOB-<n>` is how a Job's branch lands in a local working copy; the
   desktop app shells out to the `syrus` binary and quietly disables the
   feature when it's missing. Before this plan, a desktop-only user had
   no way to get the binary — the CLI was build-from-source only
   (`bin/setup --install-cli` from a repo clone they don't have).
2. **Terminal-native operators.** Inbox triage, approvals, chat, test
   plans — the same loops as the tray, composable with the shell.
3. **Local agents.** This is the sleeper use case: a Claude Code (or any
   agent) session on the operator's machine can drive Syrus through the
   CLI — list the inbox, read a Job's test plan, check out its branch,
   run it locally, leave feedback, approve. The CLI is the natural
   machine interface for *local* agents the same way the admin API is
   for remote ones.

## Phase 1 (shipped): bundle + one-click install + auto-login

- `desktop/scripts/stage-cli.mjs` cross-compiles the pure-Go CLI
  (`CGO_ENABLED=0`, no C toolchain) for darwin arm64+x64 into
  `resources/cli/`, bundled at `<Resources>/cli` (~20 MB/arch,
  compresses well in the DMG).
- Preferences → Local checkout shows CLI status and an **Install CLI**
  button: copies the right-arch binary to `~/.local/bin/syrus` (no
  admin, no sudo). No login step exists at all — the app ALREADY keeps
  `~/.syrus/credentials` in the CLI-shared format (credentialsStore.ts
  owns that file), so the CLI is signed in the moment the binary lands.
- PATH is never mutated (shell rc files are personal); if `~/.local/bin`
  isn't on PATH the UI offers the export one-liner. The app itself
  doesn't care: its availability probe and checkout exec know the
  install location directly.

## Phase 2 (shipped): the Claude skill + the setup step

A **CLI subcommand**, not a desktop feature, so clone-based users get it
too (`cli/cmd/skill.go`):

    syrus skill install [--dir ~/.claude/skills]

writes `~/.claude/skills/syrus/SKILL.md` teaching a local Claude Code
session what Syrus is and how to drive it: auth model
(`~/.syrus/credentials`), the command surface (`inbox`, `job view`,
`checkout`, `test-plan`, `approve`, `chat`), and guardrails (approve
requires explicit user intent; never checkout over dirty trees; prefer
read commands while reviewing). Skill content versioning rides the CLI
binary — reinstalling the CLI refreshes the skill.

Desktop integration: the web app window carries no IPC bridge (remote
content), so the "install as part of setup" step is main-process-owned —
once the user is signed in and lands on the home surface (post-
onboarding), a one-time native dialog offers the CLI install with an
"also add the Claude Code skill" checkbox (default on). The same combo
lives in Preferences, and the tray shows a one-click Install button when
the CLI is missing. The desktop runs the skill write through
`<installed binary> skill install`, keeping one code path with clone
users.

## Phase 3 (shipped July 2026): Windows

`stage-cli.mjs` cross-compiles `syrus-win32-{x64,arm64}.exe` alongside the
darwin binaries (naming mirrors Electron's process.platform/process.arch);
electron-builder bundles them with per-platform filters so each package
carries only its own OS's binaries. Install target is
`%LocalAppData%\Syrus\bin\syrus.exe` — deliberately NOT the plan's earlier
`Programs\Syrus\bin` suggestion, because that sits inside the NSIS
`$INSTDIR`, which electron-updater replaces wholesale on every auto-update
(the CLI would silently vanish). The per-user PATH entry is written via
the sanctioned registry API (raw HKCU\Environment read with
DoNotExpandEnvironmentNames + WM_SETTINGCHANGE broadcast; never setx,
which truncates at 1024 chars). Reinstall-while-running works through the
rename-to-.old dance (a running exe can't be overwritten but can be
renamed). Go-side Windows fixes: one shared URL-opener (rundll32, immune
to cmd metacharacters), pager falls back to direct printing when $PAGER
is unset, and .syrus.yml post_checkout hooks prefer `sh` (Git for
Windows) with a `cmd /c` fallback. `git` comes from Git for Windows.
Still wanted before advertising: a real Windows smoke pass over
`checkout` path handling (the brother test).

## Non-goals

- Homebrew tap / standalone installer: the app IS the distribution
  channel for desktop users; clone users have `bin/setup --install-cli`.
  Revisit only if headless-server operators ask.
- Auto-updating the installed CLI: for now, reinstalling from
  Preferences after an app update refreshes it. A version-mismatch nudge
  in Preferences is a cheap later add.
