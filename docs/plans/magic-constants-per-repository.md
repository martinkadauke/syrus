# Plan: per-repository magic constants → Repository columns

_Part of the [magic-constants index](magic-constants-INDEX.md). Depends
on the [site-wide plan](magic-constants-site-wide.md) landing first
because most per-repo settings inherit from a site default._

## Context

Some constants are obvious site-wide policy (retention, staleness),
but a handful express choices that legitimately differ per repository.
A monorepo might want a deeper `git clone --depth`. A flaky-CI repo
might want a higher `CI_FAILURE_CAP`. A repo with a different
review-comment label scheme might want a different skip label.

Today these are compiled-in. This plan moves them onto `repositories`
columns with NULL = "use the site default."

## Constants to migrate

| Constant | Current | Notes |
|---|---|---|
| `PollRebaseJob::REBASE_ATTEMPT_CAP` | `5` | Already implicated in production debugging (issue #74). Per-repo lets us crank it up on a long-lived branch we know we want to keep alive. |
| `PollPullRequestJob::CI_FAILURE_CAP` | `3` | How many ci_failure follow-ups before giving up. |
| `PollPullRequestJob::CI_FAILURE_WINDOW` | `24.hours` | The rolling window over which the cap applies. |
| `WorkflowWorkspace::CLONE_DEPTH` | `50` | Most projects fine with shallow; some agents need full history (mono-repos, "git log against feature branch since N months ago"). NULL or `0` = full clone. |
| `IngestPolicy::SKIP_LABEL` | `"syrus-skip"` | Already follows the pattern: `trigger_label` is per-repo today; same applies here. |
| `AgentInvocation::DEFAULT_TIMEOUT_SECONDS` | `30.minutes` | Site default in AppSetting, per-repo override here. Some repos legitimately need longer (large monorepo, slow tests). |
| `Steps::Prepare::PER_COMMAND_TIMEOUT` | `10.minutes` | Same shape — per-command budget for `bundle install` / `npm install` / etc. Repos with massive dependency trees want longer. |
| `AgentInvocation::DEFAULT_MAX_TURNS` | `200` | Site default in AppSetting, per-user override on `User#agent_max_turns` (already exists), per-repo override here. The most-specific wins (repo > user > site). |

## Schema

```sql
ALTER TABLE repositories
  ADD COLUMN rebase_attempt_cap                  INTEGER     NULL,  -- NULL = use AppSetting default
  ADD COLUMN ci_failure_cap                      INTEGER     NULL,
  ADD COLUMN ci_failure_window_seconds           INTEGER     NULL,
  ADD COLUMN clone_depth                         INTEGER     NULL,  -- NULL or 0 = full clone
  ADD COLUMN skip_label                          VARCHAR(64) NULL,  -- NULL = "syrus-skip"
  ADD COLUMN agent_timeout_seconds_override      INTEGER     NULL,
  ADD COLUMN prepare_per_command_timeout_seconds INTEGER     NULL,
  ADD COLUMN agent_max_turns_override            INTEGER     NULL;
```

All NULL by default → existing repos keep current behavior. No
migration of existing data needed.

## Resolution rule

For values that have a site default + repo override:

```ruby
class Repository < ApplicationRecord
  def effective_rebase_attempt_cap
    rebase_attempt_cap || AppSetting.current.rebase_attempt_cap
  end
  def effective_ci_failure_cap
    ci_failure_cap || AppSetting.current.ci_failure_cap
  end
  # ...
end
```

For values that have a site default + user override + repo override
(currently only `agent_max_turns`):

```ruby
def effective_agent_max_turns(user)
  agent_max_turns_override ||
    user.agent_max_turns ||
    AppSetting.current.agent_default_max_turns
end
```

Repository wins over user wins over site. Document this precedence
in `ARCHITECTURE.md`.

## UI

Extend `app/views/repositories/edit.html.erb` (or wherever repos are
edited today — there's a manage flow already that handles
`trigger_label` and `polling_enabled`) with a collapsed "Advanced"
section. Inside, every override field shows the inherited default
in faint text next to the input:

```
Rebase attempt cap   [    ]    inherits 5 from site default
Clone depth          [    ]    inherits 50 from site default; 0 = full clone
Skip label           [    ]    inherits "syrus-skip" from site default
```

Empty input = NULL = inherit. Filled = override. Unset by clearing
the field.

## Migration approach (rollout)

Order matters because of the inheritance:

1. **Schema-only**: add the nullable columns. No code change.
2. **Plumbing**: introduce `Repository#effective_*` methods that
   resolve the inheritance. Replace `CONSTANT` references with
   `repository.effective_xxx` (or threading `repository` to the
   point where the lookup happens). Spec coverage at this step:
   NULL columns produce same behavior as the old constants.
3. **UI**: add the Advanced section to the edit form. Knobs go live.

Each step is independently reversible. Step 2 is the meaty one but
each constant is small (most have 1-3 call sites).

## Validation

- `clone_depth`: NULL, 0 (full clone), or 1..10000 (shallow). Reject
  negative.
- `rebase_attempt_cap`, `ci_failure_cap`: NULL or 1..50.
- `*_seconds_*`: NULL or 1..86400 (one day cap; nobody legitimately
  wants a 30-day timeout).
- `skip_label`: NULL or matches `/\A[A-Za-z0-9_-]+\z/` to keep it
  GitHub-label-shaped.
- `agent_max_turns_override`: NULL or in `User::AGENT_MAX_TURNS_RANGE`
  (0..1000).

## Acceptance

- [ ] Schema migration adds nullable columns with no defaults
- [ ] `Repository#effective_<setting>` methods exist for each
      override and resolve repo → (user → ) site precedence
- [ ] All call sites that previously read the constant now read
      `effective_*`
- [ ] Edit form exposes the Advanced section with inheritance hints
- [ ] Spec coverage:
   - NULL value → behaves as today
   - Override → behavior changes for that repo only
   - Other repos with NULL still inherit the site default
- [ ] `ARCHITECTURE.md`'s "Repository" subsection documents the
      precedence rule

## Out of scope

- Inviting users to override at the repo level (this is admin/owner-
  only for v1)
- Per-branch overrides (overkill)
- Per-step-kind overrides beyond what's listed (e.g. per-step
  `max_turns` for `summarize_amend` — handle if it comes up)

## Cross-references

- Site-wide plan defines the AppSetting defaults each override
  inherits from
- syrus#74 (rebase cap counting bug) — landing the per-repo cap
  override doesn't fix #74, but pairs with it once the cap counts
  consecutive failures correctly
