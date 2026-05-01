# Syrus

> *Syrus est servus, qui laborem facit.*
> Syrus is the slave who does the work.

A multi-user, cross-repo issue→PR automation harness. Replaces the per-repo
`process-issues` / `process-prs` / `implement-issue` Claude skills with a
single Rails app that owns the deterministic plumbing — worktrees, branches,
PRs, cleanup — so Claude can focus on writing code.

## What problem this solves

Today the issue→PR loop runs manually per repo. Claude spends a meaningful
fraction of its context on `git worktree add`, branch naming, push retries,
and PR-creation boilerplate. When that mechanics layer goes off the rails
(stale worktrees, dirty trees, wrong base branch) the whole job dies.

**Syrus owns the mechanics. The agent only writes code.**

## Architecture (locked in)

| Choice | Decision |
| --- | --- |
| Stack | Rails 8 + MySQL + Sidekiq + Redis |
| Trigger model | Polling (no webhooks for v1 — keeps deploy boundary clean) |
| Auth | Multi-user, first signup = admin, then invite-only |
| Credentials | Per-user, encrypted at rest (Claude API key + GitHub token) |
| Workers | Separate container from the web app |
| Deploy target | K3s via `green_acres`, alongside Winston/Gloria |
| Domain | Likely `agents.green-acres.estate` (TBD) |

Inspiration: tiny_ci's lightweight self-host posture. Not a fork — fresh app.

## Roadmap

The make-or-break milestone is **M3** — once the deterministic harness opens
empty PRs reliably, swapping in the agent at M4 is mechanical.

| Milestone | Goal |
| --- | --- |
| **M0** | Rails 8 scaffold: MySQL, Sidekiq, Redis, Procfile, dev bootstrap |
| **M1** | Data model: User (first=admin), encrypted creds, RepositoryRegistry, Job state machine |
| **M2** | GitHub poller: per-user token, label-triggered issue ingestion, dedup |
| **M3** | Deterministic harness — clones, branches, opens an empty PR, cleans up. **No AI yet.** |
| **M4** | Agent invocation: replace the placeholder commit with `claude-code`, stream transcript |
| **M5** | Web UI: repo registry CRUD, job dashboard, live transcript, replay/cancel |
| **M6** | PR feedback loop: poll review comments, dispatch follow-up jobs |
| **M7** | Hardening: worker isolation, resource limits, k8s secrets, Prometheus metrics, retention |
| **M8** | Rollout: deploy to K3s, migrate first real repo, retire per-repo claude skills |

## Naming

Named after [Syrus](https://en.wikipedia.org/wiki/Publilius_Syrus) the slave
character from Thomas's high-school Latin readings. *The slave does the work,
the master takes the credit* — which is exactly the right division of labor
between this harness and the human reviewing the PR.
