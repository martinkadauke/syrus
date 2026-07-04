# Windows code signing (Azure Artifact Signing)

Background and the decision rationale live in
[`windows-desktop-plan.md`](./windows-desktop-plan.md#code-signing-researched-july-2026).
This doc is the concrete setup runbook: portal steps once, then the repo
secrets that make `.github/workflows/sign-windows-test.yml` (and later
`release-desktop.yml`) sign real installers.

Azure Artifact Signing (formerly "Trusted Signing") is Microsoft's
low-friction alternative to a traditional Authenticode certificate: $9.99/mo,
identity-validated once (government ID + selfie, ~1 business day), no
hardware token, and CI-friendly (client-secret auth, no local HSM). As of
2026 it's open to individual developers in the US and Canada.

## 1. Azure subscription

You need a **Pay-As-You-Go** subscription — free/trial subscriptions are
rejected for identity validation.

1. Sign in to <https://portal.azure.com> with the Microsoft account you want
   to hold this under (a personal/consumer account is fine).
2. Search "Subscriptions" → **Add** → **Pay-As-You-Go**. Enter a payment
   method. (If you only see "Start free" flows, go to
   <https://azure.microsoft.com/free> instead and choose the pay-as-you-go
   option there — it provisions your default directory more reliably than
   navigating to the portal cold.)
3. **Billing name and address must exactly match your government ID** —
   identity validation cross-checks these. Fix them now
   (Subscriptions → your sub → **Billing profile**) if they're off.

## 2. Create the Artifact Signing account

1. Portal search bar → **"Trusted Signing Accounts"** (the resource is
   still labeled this in some portal blades even though the product is
   branded "Azure Artifact Signing").
2. **Create** → pick a **Resource group** (create one, e.g. `syrus-signing`)
   and a **region** close to you (e.g. `East US`) — this fixes your
   `endpoint` URL for good (`https://<region>.codesigning.azure.net`, e.g.
   `eus` for East US). Note the exact region you pick.
3. Name the account (e.g. `syrus-signing`). Create it — takes under a
   minute.

## 3. Identity validation

1. Inside the new account, go to **Identity validation** → **Create**.
2. Choose **Individual**. Enter your legal name/address exactly as on your
   ID, matching the billing profile from step 1.
3. Complete the ID + selfie verification flow (AU10TIX/Entra Verified ID —
   you'll get a link, usually via email, to do this on your phone).
4. Wait for approval (historically same-day to ~1 business day). You'll see
   the validation move to **Completed** in the portal.
   **This expires every 2 years — put a reminder in your calendar**, or
   signing will silently stop working when it lapses.

## 4. Certificate profile

1. Inside the signing account → **Certificate profiles** → **Create**.
2. Profile type: **Public Trust** (this is what gives you a
   publicly-trusted Authenticode signature, as opposed to "Private Trust"
   which is for internal-only distribution).
3. Link it to the identity validation from step 3.
4. Note the **exact certificate profile name** and the **Subject/CN name**
   it issues — the CN is usually your validated legal name. You need this
   **byte-for-byte** later as `publisherName`; a mismatch fails signing.

## 5. Service principal for CI (no interactive login in Actions)

1. Portal search → **Microsoft Entra ID** → **App registrations** →
   **New registration**. Name it e.g. `syrus-release-ci`. Leave the
   default (single tenant) account type. Register.
2. From the app's **Overview** page, copy:
   - **Application (client) ID** → `AZURE_CLIENT_ID`
   - **Directory (tenant) ID** → `AZURE_TENANT_ID`
3. **Certificates & secrets** → **New client secret** → copy the secret
   **value** immediately (it's hidden after you leave the page) →
   `AZURE_CLIENT_SECRET`.
4. Grant that app permission to sign: go back to your Trusted Signing
   Account (step 2) → **Access control (IAM)** → **Add role assignment** →
   role **"Trusted Signing Certificate Profile Signer"** → assign to the
   `syrus-release-ci` app registration (search by name under "Members").

## 6. Repo secrets

Add these under the repo's **Settings → Secrets and variables → Actions →
Secrets** (on whichever repo runs the workflow — currently `tkadauke/syrus`
for `release-desktop.yml`; use your fork for `sign-windows-test.yml` if
you're testing there first):

| Secret | Value | Sensitive? |
| --- | --- | --- |
| `AZURE_TENANT_ID` | Directory (tenant) ID from step 5 | Not secret, but keep with the others |
| `AZURE_CLIENT_ID` | Application (client) ID from step 5 | Not secret, but keep with the others |
| `AZURE_CLIENT_SECRET` | The client secret **value** from step 5 | **Secret** — rotates, don't reuse elsewhere |
| `AZURE_SIGN_ENDPOINT` | `https://<region-code>.codesigning.azure.net` from step 2 | Not secret |
| `AZURE_SIGN_ACCOUNT_NAME` | The signing account name from step 2 | Not secret |
| `AZURE_SIGN_CERT_PROFILE` | The certificate profile name from step 4 | Not secret |
| `AZURE_SIGN_PUBLISHER_NAME` | The exact CN from step 4 | Not secret |

None of the last five are truly sensitive (they're account identifiers, not
credentials) — they're kept as Secrets rather than Variables purely so
there's one settings page to manage instead of two. The client secret is
the only one that actually gates signing access.

The first three (`AZURE_TENANT_ID`/`AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET`)
are read directly by the Azure SDK's `EnvironmentCredential` — nothing in
this repo needs to reference them by name. The other four are threaded
into `electron-builder`'s `win.azureSignOptions` via CLI dot-path overrides
in the workflow (see `sign-windows-test.yml`) — **not** committed as static
YAML in `desktop/electron-builder.yml`, because the mere presence of
`azureSignOptions` makes electron-builder attempt Azure signing
unconditionally (unlike the macOS `CSC_LINK` path, there's no
"absent → skip silently" fallback), which would break every unsigned
local/dev Windows cross-build done on this Mac.

## 7. Test it

Run **Actions → Sign Windows build (test) → Run workflow** (manual
dispatch only — this never fires automatically). It builds both archs,
signs via Azure, and runs `Get-AuthenticodeSignature` to verify the result
is `Valid` before uploading the installers as a workflow artifact.

## 8. Going live

Merging this into `release-desktop.yml` (so every `vX.Y.Z` tag ships a
signed Windows build alongside the mac one) is deliberately deferred until
Windows has something worth shipping publicly — phase 2 of
`windows-desktop-plan.md` (the local-install PowerShell path). Until then,
`sign-windows-test.yml` is the safe place to validate signing without
touching the live release cadence.
