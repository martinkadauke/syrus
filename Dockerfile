# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t syrus .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name syrus syrus

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.2.3
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages. Notes specific to Syrus:
#   - `git` is needed at *runtime*, not just build, because the worker
#     shells out to it for every clone / commit / push.
#   - `nodejs` + `npm` are required to install the `claude` CLI, which
#     the agent worker spawns per Run via AgentInvocation.
#   - `gnupg` and `ca-certificates` are needed for NodeSource's apt repo.
ARG NODE_MAJOR=22
ARG CLAUDE_CODE_VERSION=2.1.126
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      ca-certificates curl default-mysql-client git gnupg libjemalloc2 libvips && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install --no-install-recommends -y nodejs && \
    npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} && \
    npm cache clean --force && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
# BUNDLE_WITHOUT excludes both groups so test-only gems (capybara, vcr,
# webmock, selenium-webdriver, rspec-rails, brakeman) don't ship in the
# image. Single colon-separated string per Bundler's docs.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    RAILS_LOG_TO_STDOUT="1"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential default-libmysqlclient-dev git libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base AS app

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Bake the git SHA the image was built from. .git/ is excluded via
# .dockerignore so the running container can't compute it itself —
# bin/deploy passes --build-arg GIT_SHA=$(git rev-parse --short HEAD).
# Placed late so re-baking the SHA doesn't bust the asset/gem cache.
ARG GIT_SHA=unknown
ENV GIT_SHA=$GIT_SHA

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]




# ============================================================================
# Worker dev stage — generalist tooling so the in-pod claude-code agent can
# verify its changes against arbitrary external repos (run tests, build
# assets, etc). Companion to greenacres#16; only the worker pod uses this
# variant. Web pod stays on the lean `app` stage.
#
# Build:  docker build --target worker-dev -t syrus-worker-dev .
# ============================================================================
FROM app AS worker-dev

USER root

# Native build deps + DB clients (no servers) + CLI tooling. Each tool
# justified in greenacres#16 / syrus#114; ripgrep+fd in particular speed
# up the agent dramatically when exploring code.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential pkg-config \
      libffi-dev libssl-dev libyaml-dev \
      libxml2-dev libxslt-dev \
      zlib1g-dev libreadline-dev \
      sqlite3 postgresql-client \
      wget openssh-client jq ripgrep fd-find less vim \
      python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# mise — multi-language version manager. The agent runs `mise install`
# inside each worktree to provision the Ruby / Node / Python versions
# that worktree's .tool-versions / mise.toml declares.
RUN curl -fsSL https://mise.jdx.dev/install.sh | \
      MISE_INSTALL_PATH=/usr/local/bin/mise sh

# Package managers that don't ship with their default runtime.
# --break-system-packages is required on Debian's PEP-668-protected python.
RUN npm install -g yarn pnpm && npm cache clean --force && \
    pip3 install --break-system-packages poetry uv

# Pre-install default runtimes to /opt/mise. greenacres `seed-mise` init
# container copies these onto the worker PVC at $HOME/.local/share/mise
# on first boot so the agent doesn't pay cold-install latency for the
# common cases. Repos with non-default versions install on-demand.
ENV MISE_DATA_DIR=/opt/mise
RUN mkdir -p /opt/mise && chown -R 1000:1000 /opt/mise
USER 1000:1000
ENV PATH="/opt/mise/shims:${PATH}"
RUN mise install ruby@3.2 ruby@3.3 node@lts node@lts-1 python@3.11

# No CMD override — inherits `app`'s thrust+rails server. The worker pod's
# Deployment overrides command to `bin/jobs` per greenacres#16.
