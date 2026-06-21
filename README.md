# Syrus

> *Bis dat qui cito dat.*
> He gives twice who gives quickly. — Publilius Syrus

A multi-user, cross-repo issue→PR automation harness. Syrus owns the
deterministic plumbing — clones, branches, PRs, cleanup, retries, scheduled
tasks, and rebases — so coding agents can focus on writing code.

## What problem this solves

Today the issue→PR loop runs manually per repo. Claude spends a meaningful
fraction of its context on `git worktree add`, branch naming, push retries,
and PR-creation boilerplate. When that mechanics layer goes off the rails
(stale worktrees, dirty trees, wrong base branch) the whole job dies.

**Syrus owns the mechanics. The agent only writes code.**

## MVP Surface

| Choice | Decision |
| --- | --- |
| Stack | Rails 8 + Solid Queue (MySQL in prod, SQLite in dev/test) |
| Trigger model | External polling for GitHub issues, PR feedback, CI failures, merge state, and scheduled tasks |
| Auth | Multi-user, first signup = admin, then invite-only |
| Credentials | Per-user, encrypted at rest (GitHub token, Claude credential, Codex credential, admin API token) |
| Workers | Separate container from the web app |
| Deploy target | Kubernetes or Docker Compose; see `website/src/content/docs/deployment/` |
| Domain | Configurable via `SYRUS_APP_HOST` |

Syrus ships these MVP workflows:

- Labeled GitHub issue → prepare → implement → summarize → test plan → open PR.
- PR feedback or failing checks → prepare → agent follow-up → summarize
  amendment → push to the same PR.
- Unmergeable controlled PR branch → deterministic rebase first, then an
  agent rebase only if conflicts need judgment, followed by
  `git push --force-with-lease` against the branch SHA Syrus observed.
- Scheduled cron or one-shot task → normal issue-to-PR pipeline with
  pile-up policy (`skip`, `pile`, or `replace`).
- Direct operator-created Job → normal issue-to-PR pipeline without a
  GitHub issue.

The MVP deliberately does **not** include inbound GitHub delivery, hosted
multi-tenant sandboxing, out-of-band human escalation, shared drawing
surfaces, native GitHub suggestion application, or captured-session
continuation.

## Security Posture

The MVP assumes trusted users operating on trusted repositories. Agent runs
execute in worker-managed per-Workflow workspaces under `SYRUS_DATA_ROOT`, not
inside a hardened untrusted-code sandbox. This protects the operator checkout
from accidental agent `chdir` mistakes, but it is not a security boundary.

Run Syrus on infrastructure you control, register repositories whose code and
setup commands you are willing to execute, scope GitHub tokens narrowly, keep
secrets out of repositories, and review generated PRs before merging.

## Getting started (macOS, bare metal)

This is the full from-nothing setup on a Mac with Homebrew. Every command is
copy‑pasteable. It assumes you have **nothing** installed yet — you can run the
steps by hand, or point a coding agent at this section and let it work through
them. `bin/setup` is idempotent, so it's safe to re‑run.

What you'll end up with: Ruby 3.2.3 (pinned in `.ruby-version`), Node + npm,
Go 1.22+, libvips (for image processing), the MySQL client libraries, and the
Claude Code CLI. You do **not** run a MySQL server and you do **not** need any
secrets/master key for local dev — development and test use SQLite, and the app
self-provides Active Record encryption keys in development. MySQL only appears
because the production `mysql2` gem is compiled during `bundle install`; the
client libraries let it build, but nothing connects to MySQL locally.

### 1. Xcode Command Line Tools + Homebrew

The Command Line Tools give you a compiler, `make`, and `git`. Homebrew is the
package manager. (Both are usually already present if you've ever used `git`;
the `|| true` makes the first command safe to re-run.)

```bash
xcode-select --install || true

# Install Homebrew if `brew` isn't already on your PATH:
if ! command -v brew >/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Put brew on your PATH for this and future shells (Apple Silicon path shown):
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

> Note: the CLT and Homebrew installers may prompt for your password and a
> confirmation. On Intel Macs Homebrew lives at `/usr/local` instead of
> `/opt/homebrew` — use whichever path `brew` prints.

### 2. Install system dependencies

```bash
brew update
# rbenv/ruby-build: Ruby. node: JS + the Claude CLI. go: builds the Syrus CLI.
# vips: image processing. mysql: client libs so the mysql2 gem compiles.
brew install rbenv ruby-build node go vips mysql
# Libraries the Ruby build links against:
brew install openssl@3 readline libyaml

# Claude Code CLI — Syrus's worker shells out to `claude` to run Jobs and chats,
# so install it now, before you start the app.
npm install -g @anthropic-ai/claude-code
```

> If `bundle install` later fails to build `mysql2`, point it at Homebrew's
> mysql: `bundle config set --local build.mysql2 "--with-mysql-config=$(brew --prefix mysql)/bin/mysql_config"` and re-run `bin/setup`.

### 3. Install Ruby 3.2.3 with rbenv

```bash
# Hook rbenv into your shell (zsh is the macOS default), then reload it:
echo 'eval "$(rbenv init - zsh)"' >> ~/.zshrc
eval "$(rbenv init - zsh)"

rbenv install 3.2.3 --skip-existing
rbenv global 3.2.3
ruby -v   # should print: ruby 3.2.3
```

### 4. Clone the repository

If you already have an SSH key on your GitHub account (most developers do), just
clone:

```bash
git clone git@github.com:tkadauke/syrus.git
cd syrus
```

No SSH key yet? The GitHub CLI handles auth for you:

```bash
brew install gh
gh auth login        # choose GitHub.com → follow the browser prompt
gh repo clone tkadauke/syrus
cd syrus
```

### 5. Set up, then start the app

```bash
bin/setup    # install gems + JS deps, build the Go CLI, prepare the SQLite DBs
bin/dev      # start the app: web + worker + tailwind + JS watch, on port 3000
```

`bin/setup` installs Ruby gems (`bundle install`), JS deps (`npm ci`), builds
the Go CLI under `cli/`, registers the git merge driver, and prepares the SQLite
databases. It does **not** start the server — run `bin/dev` when you're ready.

Open **http://localhost:3000**. The **first account you create becomes the
admin**, and the first-run wizard walks you through GitHub credentials (a
classic PAT + the GitHub App), the agent, a repository, and a guided chat to
create and land your first Epic.

The wizard's **Configure agent** step handles Claude authentication: it detects
an existing `claude` login on this machine, or walks you through authorizing one
(you'll need a Claude Pro/Max/Team/Enterprise plan). The `claude` CLI you
installed in step 2 is what the worker invokes to run Jobs — without it the
wizard still loads, but agent runs can't execute. (Codex isn't wired up yet —
use Claude for now.)

### Handy commands

```bash
bin/dev          # foreman: web (rails s) + worker (bin/jobs) + tailwind + JS watch
bin/rspec        # Ruby test suite
bin/test-react   # React/Vitest suite + TypeScript typecheck
bin/test         # Ruby and React suites together
```

## Production Configuration

Production configuration is driven by environment variables so each deployment
can provide the hostnames and mail settings appropriate to its environment:

- `SYRUS_APP_HOST` — optional public app host used for URL generation and mailer links.
- `SYRUS_ALLOWED_HOSTS` — optional comma-separated host allowlist. Defaults to `SYRUS_APP_HOST`.
- `SYRUS_ASSUME_SSL` / `SYRUS_FORCE_SSL` — optional booleans, both default `true` for TLS-terminating ingress/proxy deployments. `/up` is excluded from SSL redirects and host authorization for health checks.
- `SYRUS_GITHUB_REPO` — required GitHub `owner/repo` slug for this Syrus installation's own repository; used for build revision links.
- `SYRUS_BUG_REPORT_OWNER` — required GitHub owner or organization for in-app bug reports. Syrus looks for an active `SYRUS_BUG_REPORT_OWNER/syrus` repository configured for the reporting user.
- `SYRUS_MAILER_FROM` — optional sender address for application mail. Defaults to `Syrus <noreply@SYRUS_APP_HOST>`.
- `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_AUTHENTICATION`, `SMTP_ENABLE_STARTTLS_AUTO` — optional SMTP settings. When `SMTP_ADDRESS` is absent, Rails keeps its default mail delivery configuration and delivery errors are not raised unless `SYRUS_MAILER_RAISE_DELIVERY_ERRORS=true`.

## Per-Issue Controls

Syrus recognizes `syrus-skip-prepare` on a source issue as an escape hatch for
broken prepare commands. Jobs ingested with that label skip the prepare step and
start at implementation; removing the label restores the normal prepare-first
workflow on the next ingest.

## Scheduled Tasks

Cron tasks use five-field cron expressions in UTC, but the MVP treats them
as hourly windows: the minute field is ignored for schedule matching, and a
task fires at most once in a matching UTC hour. Syrus stores a per-task
minute offset so many tasks with the same nominal schedule do not all fire on
the same poll tick.

## Credential Controls

Users can replace GitHub and agent credentials from **My credentials** by
submitting a new value. Admin API tokens are controlled separately: admins can
generate, rotate, or revoke them from the same page. Rotating invalidates the
old token immediately; revoking removes API access until a new token is
generated.

## Naming

Named after [Publilius Syrus](https://en.wikipedia.org/wiki/Publilius_Syrus),
the 1st-century-BCE Roman writer whose *Sententiae* — a collection of
one-line maxims — were schoolbook material for over a millennium and seeded
a surprising number of phrases still in everyday use. He was a writer, same
job the LLM is doing inside this harness, and his output outlived him by
two thousand years. That's the aspiration: small, durable text that
compounds. Thomas first encountered him in high-school Latin readings.
