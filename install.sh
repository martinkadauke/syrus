#!/usr/bin/env bash
# Install + run Syrus on this Mac from the PREBUILT image — no source build.
# Pulls ghcr.io/tkadauke/syrus-local and starts web + worker (SQLite, one volume).
#
# Prereqs:
#   1. A container runtime. OrbStack is easiest (bundles Compose):
#        brew install orbstack
#   2. Read access to the private GHCR package (you must be a collaborator) and a
#      one-time login:
#        echo <YOUR_GITHUB_PAT_with_read:packages> | docker login ghcr.io -u <you> --password-stdin
#
# Then just: ./install.sh   (re-runnable; reuses .env and the data volume.)
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="${SYRUS_IMAGE:-ghcr.io/tkadauke/syrus-local:latest}"
export SYRUS_IMAGE="$IMAGE"

# 1. Container runtime present?
if ! command -v docker >/dev/null; then
  echo "docker not found. Install a container runtime first (OrbStack is easiest):" >&2
  echo "  brew install orbstack" >&2
  exit 1
fi

# 1b. ...and actually reachable. A stopped OrbStack/Docker Desktop or a docker
#     context pointing at a missing socket fails here — it is NOT an auth/private
#     problem, so catch it before the pull and say so plainly.
if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but its daemon isn't reachable." >&2
  echo "Start your container runtime, then re-run ./install.sh:" >&2
  echo "  - OrbStack:       open the app (or 'orbstack start')" >&2
  echo "  - Docker Desktop: open the app" >&2
  echo "  - Colima:         colima start" >&2
  echo "If it is running, check 'docker context ls' points at the active runtime." >&2
  exit 1
fi

# 2. Resolve the Compose command (OrbStack ships the v2 plugin; Colima may need
#    'brew install docker-compose').
if docker compose version >/dev/null 2>&1; then
  compose() { docker compose "$@"; }
elif command -v docker-compose >/dev/null 2>&1; then
  compose() { docker-compose "$@"; }
else
  echo "Docker Compose not found. Install it (OrbStack bundles it):" >&2
  echo "  brew install docker-compose" >&2
  exit 1
fi

# 3. Generate .env with fresh secrets on first run.
if [ ! -f .env ]; then
  echo "== Generating .env with fresh secrets =="
  gen() { openssl rand -hex "$1"; }
  sed \
    -e "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$(gen 64)|" \
    -e "s|^ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=.*|ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(gen 32)|" \
    -e "s|^ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=.*|ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(gen 32)|" \
    -e "s|^ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=.*|ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(gen 32)|" \
    compose.env.example > .env
  echo "Wrote .env (keep it safe — it holds your instance secrets)."
fi

# 4. Pull the prebuilt image. The daemon is already known reachable (step 1b),
#    so a failure here is about the image itself — surface the real error.
echo "== Pulling $IMAGE =="
if ! compose pull; then
  echo >&2
  echo "Couldn't pull $IMAGE. See the error above. Common causes:" >&2
  echo "  - The package is private and you're not logged in. Log in once:" >&2
  echo "      echo <YOUR_PAT_with_read:packages> | docker login ghcr.io -u <your-username> --password-stdin" >&2
  echo "    (you must be a collaborator on the package)" >&2
  echo "  - No network, or the tag doesn't exist." >&2
  echo "Then re-run ./install.sh." >&2
  exit 1
fi

# 5. Start the stack.
echo "== Starting Syrus =="
compose up -d

port="$(grep -E '^SYRUS_PORT=' .env | cut -d= -f2)"
echo
echo "Syrus is running at http://localhost:${port:-3000}"
echo "  logs:  docker compose logs -f web worker   (or docker-compose ...)"
echo "  stop:  docker compose down"
echo "The first signup becomes the admin."
