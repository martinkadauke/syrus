# Sluggish-then-unreachable on staging

**Status**: open, not yet diagnosed. Captured 2026-05-02 to pick up later.

## Symptoms

- Open Syrus on staging (`https://syrus.internal.green-acres.estate`).
- Works fine for a while.
- Gradually gets sluggish.
- Eventually the page "disappears" — the browser shows a timeout error.
- From that point until the browser is fully quit and restarted, Syrus
  is unreachable from that browser. Other browsers may still work.
- Was initially observed only in Chrome (Safari was fine in parallel).
  Later observed in Safari too while Chrome had recovered. So **the
  browser-specific framing is wrong** — it's a server-side or
  network-path issue, just with timing that makes one browser exhibit
  it before the other.

## What was ruled out

| Hypothesis | Status | How |
|---|---|---|
| bfcache holding a prior page's WebSocket alive | **ruled out** | DevTools showed "Pages with WebSocket cannot enter back/forward cache" — bfcache is excluded for the page. |
| Action Cable / Turbo Stream subscription leak across navigations | **ruled out** | With "Preserve log" off, only one cable row appears after reload. The earlier "two rows" was a Preserve-log historical record, not a live socket. |
| Chrome extension interfering | not tested but **likely irrelevant** | Both browsers eventually exhibit the symptom; extension would be browser-specific. Worth a quick incognito test if it returns. |
| Service worker (Rails 8 PWA scaffold) | not tested | DevTools → Application → Service Workers — unregister and retry if it ever returns. Cheap to rule out. |
| Browser-specific HTTP/2 stickiness, QUIC, etc. | **ruled out** | Same reason as extensions — both browsers see it. |

## Live hypotheses

### 1. Puma thread pool starvation by Action Cable in-process

Rails 8 with Solid Cable runs Action Cable in the same Puma worker by
default. Each WebSocket connection holds a Puma thread. With default
`RAILS_MAX_THREADS=3` and `WEB_CONCURRENCY=2`, that's 6 thread slots
across the pod. Browser tabs across devices each open a cable
connection and eat slots. When the pool is exhausted:

- Existing requests slow (sluggish)
- New requests queue forever (timeout / page unreachable)
- Whichever browser hits an empty slot works; the others stall
- Eventually a connection drops, slot frees, things move briefly

Fits the timing: gradual onset (slots fill slowly), eventual recovery
when a connection drops, both browsers affected over time.

### 2. Traefik in the middle

Traefik sits between the user and the pod. Possible Traefik failure
modes:

- WebSocket idle-timeout cutting cable connections (default
  `idleTimeout = 90s`; Action Cable pings every 3s by default so this
  *shouldn't* hit, but worth verifying the router config)
- Connection-limit middleware queueing requests
- Backend connection pool exhaustion at the proxy
- HTTP/2 session-level issues between Traefik and the pod

## Decisive test (do this first when picking up)

**Bypass Traefik with a port-forward and reproduce.** Single test
that splits the search space cleanly.

```bash
# from a laptop with kubectl context set to the staging cluster
kubectl -n <syrus-namespace> port-forward deploy/syrus-web 3000:3000
```

Then open `http://localhost:3000` and use Syrus normally for the
duration the symptom usually takes to hit.

| Outcome | Diagnosis |
|---|---|
| Symptom doesn't recur | **Traefik** is the problem. Pursue Traefik config. |
| Symptom recurs | **Traefik is innocent**, problem is in the app or pod. Pursue Puma / Action Cable. |
| Mixed | Both contribute. |

## Correlating signals to capture during a hang

### From inside the cluster (rules out / confirms backend health)

```bash
kubectl -n <ns> exec deploy/syrus-web -- \
  curl -s -o /dev/null -w "%{http_code} in %{time_total}s\n" \
  http://localhost:3000/up
```

- Instant `200` → app is fine, problem is in front of it (Traefik /
  network).
- Hangs → app or pod is the problem.

### Active Action Cable connections vs Puma capacity

```bash
kubectl -n <ns> exec deploy/syrus-web -- bin/rails runner \
  'puts "cable_connections=#{ActionCable.server.connections.size}"; \
   stats = Puma::Stats.new; \
   puts "pool_capacity=#{stats.pool_capacity} running=#{stats.running}"'
```

If `cable_connections` ≈ `RAILS_MAX_THREADS * WEB_CONCURRENCY` and
`pool_capacity == 0`, hypothesis 1 confirmed.

### Traefik access log

Filter to the syrus router during a hang. Look for:

- `499` (client closed before backend responded) — client gave up; the
  backend was slow/unresponsive
- `504` (backend timeout) — Traefik gave up waiting on the backend
- Sustained 200s with high `Duration` — backend slow but functional

These distinguish "backend hung" from "Traefik dropped the request."

### Browser-side netlog (if reverting to per-browser diagnostics)

`chrome://net-export/` → start logging → reproduce → stop → drop the
JSON into `https://netlog-viewer.appspot.com/` to see exactly what
Chrome was doing.

## Fix paths once root cause is known

### If Puma thread pool (hypothesis 1)

1. **Bump `RAILS_MAX_THREADS`** to 16 as a quick mitigation. Pushes
   the problem out, doesn't solve it.
2. **Run Action Cable as a separate process.** Mount it as a standalone
   Rack app on a different port; point
   `Rails.application.config.action_cable.url` at it. Isolates
   WebSocket thread budget from request thread budget. The proper fix.
3. **Reduce per-page subscriptions.** Today every job page subscribes
   to its own stream; route through fewer channels per user. Smaller
   blast radius but a refactor.

### If Traefik (hypothesis 2)

- Audit IngressRoute and any middleware (timeouts, rate limit,
  connection limit) for the syrus router.
- Verify WebSocket-aware config (`websocket: true` on the router if
  using IngressRoute, or equivalent annotation).
- Look at Traefik's own metrics/dashboard for backend connection
  saturation.

## Related

- Heartbeat reaper / `worker_died` handling (PR #30, currently open) —
  separate issue but tangentially relevant: when something hangs, that
  PR's mechanism is what eventually surfaces it as a failed run.
- M7 Hardening roadmap entry — production-readiness work where
  Action-Cable-in-its-own-process likely belongs.
