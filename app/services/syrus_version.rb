require "socket"

# Build/runtime identity for this process. SHA is baked into the
# Docker image at build time by `bin/deploy` via --build-arg
# GIT_SHA=$(git rev-parse --short HEAD), surfaced through the
# GIT_SHA env var. Role comes from the K8s manifest's SYRUS_ROLE
# env var (web / worker). Locally, both fall back to "dev"/"local".
module SyrusVersion
  module_function

  def current
    ENV.fetch("GIT_SHA", "dev")
  end

  def role
    ENV.fetch("SYRUS_ROLE", "local")
  end

  def hostname
    Socket.gethostname
  end

  # True when this Rails process is one whose lifetime is worth tracking
  # in the instance_versions table — i.e. a web pod or a worker pod.
  # Skips rake tasks, console, tests, migrations. Driven by SYRUS_ROLE
  # being set explicitly in K8s manifests rather than guessing from
  # $PROGRAM_NAME.
  def server_process?
    ENV["SYRUS_ROLE"].present? && !Rails.env.test?
  end
end
