# Keeps a fork's default branch in sync with its in-instance upstream using
# GitHub's merge-upstream API (no local clone). Used by SyncForkJob for both
# the scheduled auto-sync (Repository#fork_auto_sync_enabled) and the manual
# "Sync now" action. Independent of the per-Job base branch — fork Jobs branch
# off the upstream's default directly (Job#base_on_upstream_default?). The
# point of this sync is to keep the fork's OWN default branch current so
# main-branch health/grader detection on the fork doesn't go stale.
class ForkSyncService
  # client_factory test seam mirrors the other GitHub-touching services.
  class << self
    attr_writer :client_factory

    def client_factory
      @client_factory ||= ->(repository) { GithubClient.for(repository: repository, user: repository.user) }
    end

    def call(repository:)
      new(repository).call
    end
  end

  Result = Data.define(:status, :merge_type, :base_branch, :message) do
    def synced? = status == :synced
  end

  def initialize(repository)
    @repository = repository
  end

  def call
    unless @repository.fork_syncable?
      return Result.new(status: :not_syncable, merge_type: nil, base_branch: nil,
                        message: "not a fork with an in-instance upstream")
    end

    branch = @repository.default_branch
    result = client.merge_upstream(@repository.slug, branch)
    Rails.logger.info("[ForkSync] #{@repository.slug}@#{branch} merge_type=#{result.merge_type}")
    Result.new(status: :synced, merge_type: result.merge_type, base_branch: result.base_branch,
               message: result.message)
  rescue Octokit::Conflict => e
    Rails.logger.warn("[ForkSync] #{@repository.slug} conflict: #{e.message}")
    Result.new(status: :conflict, merge_type: nil, base_branch: nil, message: strip(e.message))
  rescue Octokit::UnprocessableEntity => e
    Rails.logger.warn("[ForkSync] #{@repository.slug} not syncable: #{e.message}")
    Result.new(status: :not_syncable, merge_type: nil, base_branch: nil, message: strip(e.message))
  rescue Octokit::Error => e
    Rails.logger.warn("[ForkSync] #{@repository.slug} error: #{e.class}: #{e.message}")
    Result.new(status: :error, merge_type: nil, base_branch: nil, message: strip(e.message))
  end

  private

  def client
    self.class.client_factory.call(@repository)
  end

  def strip(message)
    message.to_s.split(%r{ // }, 2).first.to_s.strip
  end
end
