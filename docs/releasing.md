# Releasing Syrus (desktop app + backend image)

A release is a git tag `vX.Y.Z` on `tkadauke/syrus`. One tag ships **both**
halves as a tested pair:

- **GitHub Release `vX.Y.Z`** — `Syrus-X.Y.Z-{arm64,x64}.dmg` + `.zip`,
  `latest-mac.yml` (the auto-update feed), blockmaps, and a stable-named
  `Syrus.dmg` copy (arm64) for the website's
  `releases/latest/download/Syrus.dmg` permalink.
- **GHCR image `ghcr.io/tkadauke/syrus-local:X.Y.Z`** — the backend the DMG's
  bundled installer pins (`desktop/scripts/stage-backend-assets.mjs` writes
  the pin into the app's `manifest.json`).

Backend upgrades ride app auto-update: a new app version carries a new image
pin, and the app's installer pulls it. `:latest` keeps being published for
the clone-and-`install.sh` audience; nothing changes for them.

## Runbook

1. Bump `desktop/package.json` `version` to `X.Y.Z` and update
   `docs/release_notes.md`; merge to `main`.
2. Publish the backend image first (human-gated — it runs the
   `bin/test-docker` integration suite):

   ```bash
   bin/publish-image X.Y.Z --multi-arch
   ```

3. Tag and push:

   ```bash
   git tag vX.Y.Z && git push origin vX.Y.Z
   ```

4. `.github/workflows/release-desktop.yml` takes over: guards (version
   matches tag; image tag exists on GHCR; signing secrets present), builds,
   signs, notarizes, staples, verifies, and publishes the Release.

Every `vX.Y.Z` tag ships a desktop build — even for backend-only changes.
That keeps electron-updater's invariant intact: the newest release always
carries `latest-mac.yml`. Pre-releases use `X.Y.Z-beta.N` plus GitHub's
prerelease flag; electron-updater skips prereleases by default.

## One-time setup checklist

| Item | Where | Notes |
| --- | --- | --- |
| Apple Developer Program membership | developer.apple.com | $99/yr; identity verification can take days — start early |
| Developer ID Application certificate | Xcode → Settings → Accounts, or the developer portal | Export as `.p12` with the private key |
| `CSC_LINK` | repo secret | base64 of the `.p12` (`base64 -i cert.p12`) |
| `CSC_KEY_PASSWORD` | repo secret | the `.p12` export password |
| App Store Connect API key (`.p8`) | appstoreconnect.apple.com → Users and Access → Integrations | Developer role suffices for notarytool |
| `APPLE_API_KEY_P8` | repo secret | contents of the `.p8` |
| `APPLE_API_KEY_ID`, `APPLE_API_ISSUER` | repo secrets | shown on the same page |
| GHCR `syrus-local` package visibility | github.com/users/tkadauke/packages | **must be public** — every end user's install pulls it anonymously |

Secrets live on `tkadauke/syrus` (Settings → Secrets and variables →
Actions). The auto-update feed (`publish:` in `desktop/electron-builder.yml`)
is baked into shipped apps — moving Releases to another repo later strands
installed apps on the old feed.

## Why unsigned releases are blocked

The workflow refuses to publish a tag build without signing secrets:

- macOS Sequoia shows unsigned downloads a hard "Apple could not verify…"
  block (the right-click → Open bypass is gone).
- electron-updater on macOS rides Squirrel.Mac, which refuses to install an
  update into an unsigned or differently-signed app — one unsigned release
  would strand the installed base off the update path.

## Testing the pipeline without credentials

- `workflow_dispatch` → "Release desktop app" with `unsigned_dry_run` builds
  unsigned artifacts and publishes nothing.
- Local packaging check: `npm --prefix desktop run build` (unsigned without
  the Apple env vars) or `npx electron-builder --dir` for an unpacked app.
- Signing verification, once credentials exist (run from a clean, non-Dropbox
  clone — cloud-synced xattrs break codesign nondeterministically):

  ```bash
  codesign --verify --deep --strict desktop/out/mac-arm64/Syrus.app
  spctl -a -t exec -vv desktop/out/mac-arm64/Syrus.app   # expect "Notarized Developer ID"
  xcrun stapler validate desktop/out/Syrus-*.dmg
  ```

- Auto-update loop without touching the real feed: build signed `0.0.1` and
  `0.0.2`, serve `0.0.2`'s zip + `latest-mac.yml` from a local HTTP server,
  point the `0.0.1` build at it with a `dev-app-update.yml`
  (`autoUpdater.forceDevUpdateConfig`), and watch the tray gain
  "Restart to update". Then rehearse for real with a `v0.x.y-beta.1`
  prerelease tag.
