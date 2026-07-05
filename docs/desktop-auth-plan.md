# Desktop auth: where the API token lives now

Field feedback (July 2026): "Why am I entering an API key at the Connect
step when the next step is signing in with a username/password?" The
answer was: it was a relic. The token field predates the interactive app
window — when the desktop app was only a tray, the Bearer token was its
sole way to talk to the instance. Once the app gained a real sign-in
window and (round 8) self-healing token auto-provisioning, asking for a
token during setup became pure friction. This records the decision and
the resulting surface so it doesn't regress.

## The model

There are exactly two credentials, with different owners:

1. **The user session** (email + password) — owned by the person, entered
   in the app window's sign-in page. This is THE login. Nothing about it
   is desktop-specific.
2. **The machine token** (`~/.syrus/credentials`, shared with the CLI) —
   owned by the app. It exists because the tray and the CLI are separate
   processes that can't ride the window's session cookie. It is minted
   FROM the session: tokenProvisioner watches the signed-in window and
   POSTs `/api/v1/app/desktop/api_token` with the session cookie + CSRF,
   then writes the credentials file. 401s mark the stored token suspect
   and the next signed-in navigation re-mints it (round 8), so a rebuilt
   backend heals without user action.

Users should meet credential #1 and never credential #2.

## The surface, after this change

- **Onboarding "Connect to your Syrus"**: instance address ONLY. The form
  validates/normalizes live (bare IPs get http:// and :3000 assumed),
  probes `/api/v1/app/auth/status` to confirm it's really Syrus, and
  classifies failures (unreachable vs host-authorization 403 vs
  not-Syrus). No token field exists on this screen.
- **Sign-in in the app window** is the only authentication step. For
  admins — every local-install owner — the tray token mints itself on the
  next navigation.
- **Preferences → Account** keeps the manual URL+token form as the
  FALLBACK, clearly labeled as such, for the one real case that needs it:
  non-admin accounts on shared remote instances (the desktop-token
  endpoint is admin-only) — plus scripted/kiosk setups. "Get a token from
  Syrus" deep-links to the instance's own account-settings page, where
  generate/rotate/revoke already live. The desktop app deliberately grows
  no token-generation UI of its own.

## Non-goals / future

- Making the desktop-token endpoint available to non-admins (would let
  the Preferences fallback disappear entirely) — a server-side policy
  decision, revisit when a real multi-user remote deployment asks.
- OAuth-style device flow — overkill while sign-in lives in an embedded
  window that shares the instance origin.
