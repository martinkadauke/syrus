---
title: Getting Started
description: Get from a fresh Syrus install to the first successful Job and pull request.
---

# Getting Started

Syrus turns GitHub issues, direct prompts, PR feedback, retries, and
rebases into agent runs. It owns the deterministic plumbing: clone the
repository, prepare the workspace, invoke the agent, capture the diff,
push a branch, and open or update the pull request.

This guide gets you from a fresh Syrus instance to one successful Job.
That first success is deliberately small: prove credentials, repository
access, polling, workspace setup, agent invocation, push, and PR creation
before asking Syrus to do bigger work.

## Choose The First Path

Use the path that answers the question you have right now.

| If you want to... | Start here | What you will see |
| --- | --- | --- |
| Evaluate agent behavior against code on your machine | [Try it locally](/docs/deployment/try-it-locally) | One container runs once, prints a local diff, and exits. No GitHub access, database, users, or PR. |
| Try the full product loop for yourself or a small team | [Docker Compose](/docs/deployment/docker-compose) or your operator-provided setup | Web UI, worker, database, repository polling, Job history, and a real GitHub PR. |
| Self-host on shared infrastructure | [Deployment](/docs/deployment) and [Kubernetes](/docs/deployment/kubernetes) | The same app on your own infrastructure, once you have chosen ingress, storage, secrets, backups, and operations. |

:::note
The local evaluation path is useful, but it is not the full product
sequence. It does not create users, poll GitHub, add repositories, or open
pull requests.
:::

:::caution
Some packaging pieces are still landing. The Docker Compose and
Kubernetes pages describe the target operating shape and the honest status
of the published artifacts. If your checkout does not include the Compose
file or cluster packaging yet, use the deployment path your operator
provides rather than filling in missing production decisions from this
guide.
:::

## Local Evaluation

The shortest evaluation is:

1. Open a Git checkout on your machine.
2. Export an agent credential for the local runner.
3. Run the single-container command from
   [Try it locally](/docs/deployment/try-it-locally).
4. Inspect the printed diff or write it to `syrus.diff`.

That path runs a temporary local-dev Job through the standard
`prepare -> implement` work, then stops. Use it to answer "can Syrus make
a plausible change in this codebase?" Continue with the hosted setup when
you want the real `issue -> Job -> Workflow -> PR` loop.

## Hosted Setup

A real Syrus instance needs:

- A web process for signup, credentials, repository settings, dashboards,
  transcripts, and PR links.
- A worker process for pollers, preparation commands, agent runs, pushes,
  PR creation, reapers, and workspace cleanup.
- MySQL for users, encrypted credentials, repositories, Jobs, Workflows,
  Runs, logs, artifacts, and queue state.
- A durable `$SYRUS_DATA_ROOT` volume on workers for clone caches and
  workflow workspaces.
- Stable Rails secrets, especially `RAILS_MASTER_KEY`, so encrypted user
  credentials stay decryptable across restarts.

The first-run checklist in the authenticated UI follows this sequence:
account and admin access, GitHub credentials, agent credentials and
provider, repository, meeting Syrus in chat, then landing your first Epic.
While you are still working through the early steps, the other top-level
tabs are hidden and the **Syrus** brand link returns you to onboarding —
the only tab is **Setup** (which opens the onboarding checklist). The
moment you start the onboarding chat, the rest of the tabs appear and the
**Syrus** brand link opens that chat. Onboarding completes when your first
Epic lands (all of its child Jobs merge), at which point the **Setup** tab
drops off the navigation entirely.

## First Successful Run

Keep the first request boring. A typo fix, one tiny docs update, or one
obvious failing test is better than a broad refactor. The goal is to
verify the product sequence.

### 1. Create the first admin

Open the web UI and sign up. The first user becomes an admin and can
complete instance-level setup such as GitHub App registration.

After signup, open **First-run setup** or **My credentials**. The setup
screen should point you at the next missing step until at least one Job
has closed successfully.

### 2. Add credentials and choose a provider

In **My credentials**, choose your default agent provider and add the
matching credential:

- **Claude** uses a Claude OAuth token. On the **First-run setup**
  checklist, the **Configure agent** step opens a guided modal: it first
  checks whether `claude --print` already works on this machine (common on
  bare-metal installs where you have already run `claude login`), and if not,
  an **Authorize with Claude** button opens the subscription OAuth flow in a
  new tab. Approve access, copy the short code Claude shows you, and paste it
  back into the modal — Syrus exchanges it for a long-lived token and tests it
  on the spot. No terminal needed; requires a Claude Pro, Max, Team, or
  Enterprise plan. (You can also paste a `claude setup-token` value directly in
  **My credentials**.)
- **Codex** uses either a Codex API key or ChatGPT `auth.json`,
  depending on the selected Codex authentication mode.

Set **Max turns** to the cap you want for agent runs. The default is meant
to prevent runaway loops while still allowing normal implementation work.

Then configure GitHub access. Syrus considers GitHub authentication ready
when either a user PAT exists or a GitHub App is registered for the
instance. On the **First-run setup** checklist, the **Configure GitHub**
step opens a guided modal with two tabs — **GitHub App** (recommended) and
**Personal access token**.

- A **GitHub App installation** is preferred. On the **GitHub App** tab
  (admin only), Syrus creates the singleton Syrus GitHub App from a manifest:
  click the button, GitHub creates the App and redirects back, then Syrus
  shows an **Install** link so you can install it on the repositories it
  should manage. Registering the App satisfies the GitHub step; repositories
  with an active installation use App credentials (actions appear as a bot,
  with an independent rate limit and auto-refreshing tokens).
- A **GitHub personal access token** is the fallback credential. It must
  be able to list issues, read PRs and checks, push branches, open pull
  requests, and post updates for the repositories Syrus will manage. On the
  **Personal access token** tab, Syrus links straight to
  [github.com/settings/tokens](https://github.com/settings/tokens), tells you
  to create a *classic* token with **No expiration** and the `repo` and
  `workflow` scopes, then verifies the token the moment you paste it — a green
  check confirms it works, while a clear message flags an invalid token or a
  missing scope before you save.

Syrus records the credential mode on repositories and Jobs so operators
can tell whether a run used App credentials or PAT fallback.

### 3. Add a repository

On the **First-run setup** checklist, the **Add repository** step opens a
guided modal for your *first* repository. It walks you through GitHub
dropdowns: pick a **User/Org**, then the **Repository** dropdown for that owner
appears, and once you choose a repository the **Default branch** dropdown lists
its branches with `main`/`master` pre-selected. (There is no free-text entry —
the dropdowns come from GitHub, so if they can't load you fix **Configure
GitHub** first.) The modal applies the `syrus` trigger label by default,
inherits the default agent you chose earlier, and turns on auto-merge plus the
standard repository defaults. It skips the upstream/fork fields. Additional
repositories — and any fine-tuning, including the trigger label — happen later
from the full **Repositories** page.

To add more repositories after the first, open **Repositories**. You
can pick from GitHub when credentials can list accessible
repositories, or enter the owner and repository name manually.

Confirm these settings:

- **Default branch** is the branch Syrus should clone, diff against, and
  target for PRs.
- **Trigger label** is the issue label that creates Jobs. The default is
  `syrus`.
- **Polling enabled** is on for issue ingestion.
- **Default agent** is blank unless this repository should override your
  user default provider.
- **Run prepare step** is on unless this repository intentionally needs no
  setup.

If the repository needs more than one setup command, add `.syrus.yml` to
the target repository:

```yaml
prepare:
  - bundle config set --local path vendor/bundle
  - bundle install --jobs 4
  - npm ci
```

If `.syrus.yml` is missing, Syrus auto-detects one common setup command
from lockfiles such as `Gemfile`, `yarn.lock`, `pnpm-lock.yaml`,
`package-lock.json`, or `package.json`. Use `prepare: []` or
`prepare: false` only when no setup should run.

### 4. Meet Syrus in chat and land your first Epic

The final first-run step sends you into a **Syrus chat**. Click **Start
Syrus chat** on the checklist; Syrus opens a chat attached to your
repository and greets you. It explains how Jobs and Epics work, then helps
you create your first **Epic**. The recommended first Epic is onboarding
the repository itself to Syrus — for example adding an `AGENTS.md` (an
agent guide) and a `.syrus.yml` with `prepare` commands and `graders`
(test/lint/typecheck commands) that fit the repo — but you can pick a
different first Epic.

Syrus proposes the Epic and its child Jobs as a proposal card you accept.
Once accepted, Syrus offers to move the Epic to **In Progress**, which is
what actually triggers it to implement the Jobs. Within an Epic, **every**
child Job must be approved before **any** of them land — the Epic lands
atomically as a unit.

Once the Jobs run, the GitHub loop is the same as for any Job. You can also
file work directly: create or edit a GitHub issue in the registered
repository and add the trigger label, or create a **direct Job** from the
web UI. Syrus polls GitHub instead of receiving inbound webhooks, so a
labelled issue's Job may not appear immediately.

### 5. Watch the Job, Workflow, and Run

Open the Job from the dashboard or setup screen. The first labelled issue
normally creates an `initial` Workflow with these Steps:

```text
prepare
implement
summarize
pr_open
```

Watch these checkpoints:

- The Job leaves the queue and shows the selected agent provider.
- `prepare` succeeds, skips by configuration, or records a clear setup
  failure.
- `implement` starts a Run, streams transcript output, and captures the
  agent's commits.
- The Run or Workflow shows the captured diff.
- `summarize` records PR title and body.
- `pr_open` pushes the Syrus branch and attaches the GitHub PR number.

If the Job fails, keep the Job page as the starting point. It contains
the Workflow, Step, Run, logs, transcript, diff, and retry actions needed
for diagnosis.

### 6. Review the PR result

Open the PR from the Job page. Review it like any other pull request:
read the diff, check CI, comment, request changes, approve, or merge.

If you comment on the PR, Syrus can pick up feedback on a later PR poll
and create a follow-up Workflow on the same Job. If CI failures are
enabled for your installation, failing checks can also create repair
Workflows on Syrus-owned PRs.

The first-run guide is complete when your first Epic lands (all of its
child Jobs merge); the **Setup** tab then drops off the navigation.
After that, the dashboard becomes the normal working surface for Jobs,
PRs, retries, schedules, direct Jobs, and operational follow-up. The Jobs
list opens to the Inbox smart folder by default so actionable work is
first; use More -> All jobs when you need the unfiltered Job list.

If no Job appears, start with
[the poller troubleshooting checklist](/docs/troubleshooting#the-poller-never-picks-up-my-issue).
If a Job appears but no PR is created, start with
[PR creation failed](/docs/troubleshooting#pr-creation-failed).

## Tiny Glossary

Syrus uses five core words throughout the UI and API:

| Term | Short version |
| --- | --- |
| **Epic** | A group of related Jobs in one repository, useful when a goal needs several sequenced PRs. |
| **Job** | The thread of work for one source of truth: a GitHub issue, scheduled task, or ad-hoc prompt. |
| **Workflow** | One attempt to handle that Job. |
| **Step** | One stage inside a Workflow, such as prepare, implement, summarize, or push. |
| **Run** | One execution attempt for a Step, carrying prompt, agent metadata, diff, and PR copy. |

For the deeper version, including state machines and trigger kinds,
read [Concepts](/docs/concepts).

## Where To Go Next

- [Evaluate Syrus locally](/docs/deployment/try-it-locally) if you want
  a quick diff before deploying anything.
- [What is Syrus?](/docs/what-is-syrus) for the product model.
- [Why use Syrus?](/docs/why-use-syrus) for fit and trade-offs.
- [Deployment](/docs/deployment) if you are choosing between local,
  Compose, and Kubernetes.
- [Concepts](/docs/concepts) if you want the mental model behind Epics
  and the Job → Workflow → Step → Run vocabulary.
