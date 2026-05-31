class RepositoriesController < ApplicationController
  before_action :load_repository, only: %i[
    poll archive unarchive retry_failed_jobs
  ]

  PER_PAGE = 20

  def poll
    if @repository.archived?
      redirect_to repositories_path, alert: "#{@repository.slug} is archived — unarchive it first."
    else
      PollRepositoryJob.perform_later(@repository.id, force: true)
      redirect_to repository_path(@repository), notice: "Polling #{@repository.slug} now…"
    end
  end

  def archive
    @repository.archive!
    redirect_to repositories_path, notice: "#{@repository.slug} archived."
  end

  # Bulk Retry across every open Job in this repo whose latest Run
  # ended in failure. Same per-Job semantics as the "Retry" button on
  # Job#show: spawns a Workflows::Retry on the existing branch, no
  # PR re-opening. Skips Jobs with an active Run (they're already
  # making progress) and closed Jobs (Reopen is still a manual call,
  # since "I want this Job alive again" is a deliberate decision).
  def retry_failed_jobs
    eligible = @repository.jobs.open_threads.select do |j|
      !j.any_active_run? && j.current_run&.failed?
    end

    if eligible.empty?
      redirect_to repository_path(@repository), alert: "No failed jobs to retry."
      return
    end

    agent_provider = @repository.effective_agent_provider
    retried = eligible.count do |job|
      RetryWorkflowEnqueuer.call(
        job: job,
        agent_provider: agent_provider,
        provider_validation: :none
      ).success?
    end

    redirect_to repository_path(@repository),
                notice: "Retry enqueued for #{helpers.pluralize(retried, 'failed job')} with #{agent_provider.titleize}."
  end

  def unarchive
    @repository.unarchive!
    redirect_to repositories_path, notice: "#{@repository.slug} unarchived. Re-enable polling to start ingestion again."
  end

  private

  def load_repository
    @repository = Current.user.repositories.find(params[:id])
  end
end
