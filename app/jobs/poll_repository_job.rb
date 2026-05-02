class PollRepositoryJob < ApplicationJob
  queue_as :default

  # Serialize per-repo polling so a manual "Poll now" click can't race
  # the recurring schedule past the dedup check.
  limits_concurrency to: 1, key: ->(repo_id, *) { "poll:#{repo_id}" }

  def perform(repository_id, force: false)
    repository = Repository.find_by(id: repository_id)
    return unless repository
    # Archive is stricter than polling-off — it blocks even force: true
    # so a stale "Poll now" tab can't reanimate an archived repo.
    return if repository.archived?
    return unless force || repository.polling_enabled?

    issues = GithubClient.for(repository.user)
                         .issues_with_label(repository.slug, repository.trigger_label)

    issues.each do |issue|
      ingest(issue, repository)
    end
  end

  private

  def ingest(issue, repository)
    decision = IngestPolicy.evaluate(issue, repository)
    unless decision.allow
      Rails.logger.info("[PollRepositoryJob] #{repository.slug}##{issue.number} skipped: #{decision.reason}")
      return
    end

    # Dedup against ANY prior Job for this issue, not just active ones —
    # otherwise a succeeded/failed Job on the same issue stops protecting
    # against re-ingest, and every poll after that opens a fresh PR.
    # To intentionally re-process an issue, use the Replay button on the
    # original Job (which bypasses this poller).
    if existing_job_for_issue?(repository, issue.number)
      Rails.logger.info("[PollRepositoryJob] #{repository.slug}##{issue.number} dedup: prior Job exists")
      return
    end

    Job.create!(
      user: repository.user,
      repository: repository,
      issue_number: issue.number
    )
  end

  def existing_job_for_issue?(repository, issue_number)
    Job.exists?(repository_id: repository.id, issue_number: issue_number)
  end
end
