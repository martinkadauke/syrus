class PollMainBranchHealthJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(repo_id, *) { "poll_main_health:#{repo_id}" }

  def perform(repository_id)
    repository = Repository.find_by(id: repository_id)
    return unless repository
    return if repository.archived?

    client = GithubClient.for(repository: repository, user: repository.user)

    sha = client.branch_head_sha(repository.slug, repository.default_branch)
    return unless sha

    sha_changed = sha != repository.last_health_checked_sha

    # Health is scoped to the default-branch SHA. When main advances, stale
    # CI/grader states from the prior SHA must not leak onto the new one while
    # GitHub checks or the main-grader workflow are still running.
    if sha_changed
      repository.update_columns(
        last_health_checked_sha: sha,
        ci_health: "unknown",
        grader_health: "unknown"
      )
      repository.reload
      MainGraderWorkflowJob.perform_later(repository.id, sha)
    end

    # Skip when SHA unchanged and health is already known — no new information.
    return if !sha_changed && !repository.main_health_unknown?

    previous_health = repository.main_health
    already_recorded_no_ci = repository.ci_health_not_configured? && repository.last_health_checked_sha == sha
    summary = client.check_runs_summary_for(repository.slug, sha)

    unless summary[:any?]
      repository.update_columns(
        ci_health: "not_configured",
        last_health_checked_sha: sha
      )
      repository.reload
      unless already_recorded_no_ci
        MainBranchHealthCheck.record_ci_poll(
          repository: repository,
          sha: sha,
          ci_health: "not_configured",
          ci_failed_checks: []
        )
      end
      MainHealthChangedService.on_health_change!(repository) if repository.main_health != previous_health
      return
    end

    if summary[:pending?]
      # Checks still running. Keep ci_health unknown so later polls keep
      # refreshing this same SHA until GitHub reaches a terminal result.
      return
    end

    new_ci_health = if summary[:any_failed?]
      "broken"
    elsif summary[:all_passed?]
      "healthy"
    end

    if new_ci_health
      repository.update_columns(
        ci_health: new_ci_health,
        last_health_checked_sha: sha
      )
      MainBranchHealthCheck.record_ci_poll(
        repository: repository,
        sha: sha,
        ci_health: new_ci_health,
        ci_failed_checks: summary[:failed_checks]
      )
    end

    repository.reload
    if repository.main_health != previous_health
      MainHealthChangedService.on_health_change!(repository)
    end
  end
end
