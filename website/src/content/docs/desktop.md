---
title: Desktop App (macOS)
description: Download Syrus.app — a guided local install, the full web UI in a native window, and a menu-bar inbox.
---

# Desktop App (macOS)

The Syrus desktop app is the easiest way to run Syrus: download a DMG,
double-click Syrus inside it (the app installs itself into
`~/Applications` and relaunches from there), and let it set everything
up. No dragging, no terminal, no clone, no manual configuration.

**[Download Syrus for Mac](https://github.com/tkadauke/syrus/releases/latest/download/Syrus.dmg)**
(Apple Silicon) ·
**[Intel Macs](https://github.com/tkadauke/syrus/releases/latest/download/Syrus-Intel.dmg)** ·
other artifacts on the [releases page](https://github.com/tkadauke/syrus/releases).

## What you get

- **A guided first-run setup.** On first launch, choose between
  installing Syrus locally or connecting to an existing instance your
  team already runs. The local path drives the same Docker install the
  CLI uses (`install.sh --docker`), streamed into a progress view — it
  detects an existing Docker runtime (OrbStack, Docker Desktop, or
  Colima), walks you through installing OrbStack when there is none,
  and adopts a previous CLI install instead of clobbering it.
- **The full Syrus web app in a native window.** Jobs, Epics, chats,
  repositories, insights — everything. External links (GitHub PRs,
  issues) open in your default browser.
- **The menu-bar inbox.** Implemented and failed Jobs, notifications with
  badge counts, approve/retry/feedback actions, and a compose shortcut —
  one keyboard shortcut away. For admins — which includes the first (and
  usually only) user of a local install — signing in inside the app window
  wires the menu bar up automatically; there is no token to copy.
  Non-admin users on a shared remote instance paste an API token into
  Preferences instead.
- **Lifecycle management.** The app starts your local Syrus when it
  launches and leaves it running when you quit, so GitHub polling and
  agent runs continue in the background. Start, stop, and restart live
  in the **Backend** menu.
- **Automatic updates.** The app updates itself, and each app release
  pins the exact backend image version it was tested with. After an app
  update, the next launch offers to bring the local backend up to the
  pinned version — the update pulls the new image and restarts the
  backend, so the app asks first instead of doing it behind your back.

## Requirements

- macOS 13 or later (Apple Silicon DMG is the primary artifact; an
  Intel build is published alongside it).
- A Docker runtime for the local install: [OrbStack](https://orbstack.dev)
  (recommended; the app guides you through it), Docker Desktop, or
  Colima. Connecting to a remote Syrus instance needs no Docker at all.
- ~2 GB of disk for the backend image, plus whatever your repositories'
  clones need.

## Where things live

| What | Where |
| --- | --- |
| Install configuration (`.env` with your instance secrets, compose file, install log) | `~/.syrus/local/` |
| Databases, clone cache, workflow workspaces | Docker volumes `syrus_syrus-data` and `syrus_syrus-search` |
| Menu-bar / CLI credentials | `~/.syrus/credentials` |
| App settings (window state, hotkey, checkout paths) | `~/Library/Application Support/Syrus/` |

Keep `~/.syrus/local/.env` safe: it holds the encryption keys for your
instance's database. Deleting it while the data volume exists makes the
existing data undecryptable — the app and the installer both guard
against this and will ask you to locate the original `.env` or
explicitly start fresh.

## Coexisting with a CLI install

The app and `./install.sh --docker` manage the same Docker project
(`syrus`). If you installed from a clone before, the app detects the
existing data volume during setup and offers to adopt it — point it at
your original `.env` (it copies the file, never moves it). See the
[Docker Compose](/docs/deployment/docker-compose#driving-the-installer-from-automation)
page for the underlying installer contract.

## Starting over

**Syrus → Run Setup Again…** forgets the app's backend configuration and
reopens the first-run setup — useful after moving your instance, wiping
Docker, or pointing the app at the wrong URL. It never deletes your
credentials or your Syrus data. If the app detects that Docker is healthy
but the Syrus data volume is gone entirely, it offers this itself.

## Uninstall

1. Quit Syrus and stop the stack: **Backend → Stop Syrus** (or
   `docker compose -p syrus stop`).
2. Delete `Syrus.app` from Applications.
3. To remove all data too:
   `docker compose -p syrus down -v` (deletes the database and clone
   cache — irreversible), then delete `~/.syrus/`.
