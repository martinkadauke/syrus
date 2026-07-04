# Syrus CLI × desktop app — why, how, and what ships when

Status: phase 1 (bundle + one-click install + auto-login) implemented on
`desktop-app/11-e2e-polish`; phases 2–3 planned.

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

## Phase 2 (planned): the Claude skill

Yes, this should exist — as a **CLI subcommand**, not a desktop feature,
so clone-based users get it too:

    syrus skill install [--dir ~/.claude/skills]

writes `~/.claude/skills/syrus/SKILL.md` teaching a local Claude Code
session what Syrus is and how to drive it: auth model
(`~/.syrus/credentials`), the command surface (`inbox`, `job view`,
`job approve`, `job feedback`, `checkout`, `test-plan`, `chat`), repo
detection (commands scope to `origin` by default), and guardrails
(approve requires explicit user intent; never checkout over dirty
trees). The desktop's post-install panel gains a one-liner offer once
the subcommand exists. Skill content versioning rides the CLI binary —
reinstalling the CLI refreshes the skill.

## Phase 3 (planned): Windows

The CLI is Go and already branches on `runtime.GOOS` (URL-opening uses
`cmd /c start`); `git` comes from Git for Windows. Cross-compile
windows/amd64+arm64 in `stage-cli.mjs`, bundle in the NSIS payload,
install to `%LocalAppData%\Programs\Syrus\bin\syrus.exe` and offer the
PATH addition (per-user `Path` registry value — unlike POSIX shell rc
files, this one has a sanctioned API). Needs a real Windows smoke pass
over `checkout` path handling before it's advertised.

## Non-goals

- Homebrew tap / standalone installer: the app IS the distribution
  channel for desktop users; clone users have `bin/setup --install-cli`.
  Revisit only if headless-server operators ask.
- Auto-updating the installed CLI: for now, reinstalling from
  Preferences after an app update refreshes it. A version-mismatch nudge
  in Preferences is a cheap later add.
