# Preview Environments

Preview environments let operators and reviewers access a live, running copy of the target application for testing before approving a PR. The web process handles subdomain-based routing to the preview service.

## URL routing

Preview environments are accessed via subdomains, not paths:

```
http://preview-{job_id}.{SYRUS_PREVIEW_BASE_DOMAIN}
```

Path-based proxying is intentionally not used — it causes CSRF failures, broken absolute URL generation, and broken redirects in most web frameworks.

## Configuration

### `SYRUS_PREVIEW_BASE_DOMAIN`

Controls the base domain for preview subdomains. Default: `lvh.me`.

| Environment | Setting |
|---|---|
| Local dev | Use the default `lvh.me` — all `*.lvh.me` subdomains resolve to `127.0.0.1` via public DNS, requiring no `/etc/hosts` changes |
| Production | Set to your domain (e.g. `syrus.yourdomain.com`) and add a wildcard DNS record (`*.syrus.yourdomain.com → your web server IP`) |

### `SYRUS_PREVIEW_PORT_MIN` / `SYRUS_PREVIEW_PORT_MAX`

Port range the preview service allocates from when spawning preview apps. Defaults: `20000`–`29999`.

## Architecture

### Web process: `PreviewProxyMiddleware`

The middleware is inserted at position 0 (first in the stack) so preview subdomains are handled before host authorization or SSL redirect middleware can reject them.

For each incoming request:

1. The `Host` header is matched against `preview-(\d+).{base_domain}`.
2. If matched, Syrus looks up a `PreviewEnvironment` with that `job_id` in `running` state.
3. If found: the request is reverse-proxied to the preview app at `internal_host:port`, and `last_activity_at` / `expires_at` are refreshed to extend the TTL.
4. If not found (environment not running, never started, or expired): a 503 response is returned with a message directing the user to the Syrus UI.
5. If the host doesn't match the preview pattern: the request falls through to the normal Rails application.

The proxy preserves the public preview `Host` header when forwarding to the preview app, and production host authorization automatically allows `preview-{job_id}.<SYRUS_PREVIEW_BASE_DOMAIN>`. Preview child processes also receive a `SYRUS_ALLOWED_HOSTS` value that includes their own preview hostname, so previewing an older Syrus branch still works even if that branch predates the preview-host allowlist. Rewriting the upstream request to the internal service name would cause Rails preview apps to reject requests with HostAuthorization 403s.

### Preview service process

The `preview` service (`bin/preview`, `Procfile.dev`) is a separate long-running process that manages preview app child processes. It is not involved in request routing.

Preview apps do not reuse workflow workspaces: successful workflow workspaces are cleaned up as part of normal workflow lifecycle. When an operator starts a preview, the preview service materializes a fresh checkout under `$SYRUS_DATA_ROOT/previews/<preview_environment_id>/` at the Job's PR branch, runs the preview seed command there, and starts the app from that checkout.

Each preview server child process is recorded as a `SpawnedProcess` with `kind=preview`, including `pid`, `pgid`, command, workdir, and preview/job identifiers in `resource_attribution`. This keeps preview processes visible in the admin Spawned Processes UI and lets the normal spawned-process supervisor/audit path detect exits and honor operator kill requests.

## Lifecycle

- Start: operator clicks "Start Preview" in the Syrus UI → preview service creates a fresh preview checkout, runs seed commands, then spawns the app.
- Inactivity TTL: 10 minutes of no proxied traffic causes the preview service to stop the environment.
- TTL reset: each proxied request through `PreviewProxyMiddleware` resets `last_activity_at` and extends `expires_at`.
- Failure: if the checkout, preview command resolution, port allocation, seed/app start, or health check fails, the environment is marked `failed` with an error message. It must not remain indefinitely in `starting`.

## Production setup

1. Set `SYRUS_PREVIEW_BASE_DOMAIN` to your domain.
2. Add a wildcard DNS record: `*.{your_domain} → your web server IP`.
3. Ensure your TLS terminator (Traefik, nginx, etc.) passes the `Host` header through to Rails.
4. The preview service must run alongside web and worker (`SYRUS_ROLE=preview bin/preview`).
