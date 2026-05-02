module ApplicationHelper
  GITHUB_REPO = "tkadauke/syrus".freeze

  # The git SHA the running image was built from. bin/deploy passes
  # --build-arg GIT_SHA=$(git rev-parse --short HEAD) at build time;
  # the Dockerfile turns that into a runtime ENV. In local dev (no
  # baked SHA) we just say "dev".
  def app_revision
    ENV["GIT_SHA"].presence || "dev"
  end

  # GitHub URL for the running revision, or nil for local dev.
  def app_revision_url
    return nil if app_revision == "dev"
    "https://github.com/#{GITHUB_REPO}/commit/#{app_revision}"
  end

  # "production" / "staging" / "development". Set explicitly via
  # SYRUS_ENV when the K3s manifest needs to distinguish staging
  # from production (both run RAILS_ENV=production); falls back to
  # Rails.env so dev/test render correctly without extra config.
  def app_env_label
    ENV["SYRUS_ENV"].presence || Rails.env
  end
end
