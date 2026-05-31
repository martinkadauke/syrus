class RepositoriesController < ApplicationController
  before_action :load_repository, only: %i[
    poll archive unarchive retry_failed_jobs
    issues comment_issue close_issue delegate_issue bulk_issues
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

  def issues
    @state = params.fetch(:state, "open").presence_in(%w[open closed]) || "open"
    @issues = GithubClient.for(repository: @repository, user: Current.user).list_all_issues(@repository.slug, state: @state).first(50)
  rescue ArgumentError
    @issues = []
    flash.now[:alert] = "No GitHub token configured — add one in Settings."
  rescue Octokit::Error => e
    @issues = []
    flash.now[:alert] = "GitHub error: #{e.message}"
  end

  def comment_issue
    issue_number = params.require(:issue_number).to_i
    body = params[:comment_body].to_s.strip
    if body.blank?
      redirect_to issues_repository_path(@repository, state: params[:state]), alert: "Comment cannot be blank."
      return
    end
    GithubClient.for(repository: @repository, user: Current.user).add_issue_comment(
      @repository.slug,
      issue_number,
      body,
      on_behalf_of: Current.user
    )
    redirect_to issues_repository_path(@repository, state: params[:state]), notice: "Comment added to ##{issue_number}."
  rescue => e
    redirect_to issues_repository_path(@repository, state: params[:state]), alert: "Failed to add comment: #{e.message}"
  end

  def close_issue
    issue_number = params.require(:issue_number).to_i
    GithubClient.for(repository: @repository, user: Current.user).close_issue(@repository.slug, issue_number)
    redirect_to issues_repository_path(@repository, state: params[:state]), notice: "Issue ##{issue_number} closed."
  rescue => e
    redirect_to issues_repository_path(@repository, state: params[:state]), alert: "Failed to close issue: #{e.message}"
  end

  def delegate_issue
    issue_number = params.require(:issue_number).to_i
    GithubClient.for(repository: @repository, user: Current.user).add_label_to_issue(@repository.slug, issue_number, @repository.trigger_label)
    redirect_to issues_repository_path(@repository, state: params[:state]), notice: "Issue ##{issue_number} delegated to Syrus."
  rescue => e
    redirect_to issues_repository_path(@repository, state: params[:state]), alert: "Failed to delegate issue: #{e.message}"
  end

  def bulk_issues
    issue_numbers = selected_issue_numbers
    if issue_numbers.empty?
      redirect_to issues_repository_path(@repository, state: params[:state]), alert: "Select at least one issue."
      return
    end

    case params[:bulk_action]
    when "delegate"
      bulk_delegate_issues(issue_numbers)
    when "close"
      bulk_close_issues(issue_numbers)
    else
      redirect_to issues_repository_path(@repository, state: params[:state]), alert: "Choose a bulk action."
    end
  end

  private

  def load_repository
    @repository = Current.user.repositories.find(params[:id])
  end

  def load_github_issues
    @state = params.fetch(:state, "open").presence_in(%w[open closed]) || "open"
    @issues = GithubClient.for(repository: @repository, user: Current.user).list_all_issues(@repository.slug, state: @state).first(50)
  rescue ArgumentError
    @issues = []
    flash.now[:alert] = "No GitHub token configured — add one in Settings."
  rescue Octokit::Error => e
    @issues = []
    flash.now[:alert] = "GitHub error: #{e.message}"
  end

  def selected_issue_numbers
    Array(params[:issue_numbers]).filter_map do |number|
      Integer(number, exception: false)
    end.select(&:positive?).uniq
  end

  def bulk_delegate_issues(issue_numbers)
    client = GithubClient.for(repository: @repository, user: Current.user)
    issue_numbers.each do |issue_number|
      client.add_label_to_issue(@repository.slug, issue_number, @repository.trigger_label)
    end

    redirect_to issues_repository_path(@repository, state: params[:state]),
                notice: "#{helpers.pluralize(issue_numbers.size, 'issue')} delegated to Syrus."
  rescue => e
    redirect_to issues_repository_path(@repository, state: params[:state]), alert: "Failed to delegate issues: #{e.message}"
  end

  def bulk_close_issues(issue_numbers)
    client = GithubClient.for(repository: @repository, user: Current.user)
    issue_numbers.each do |issue_number|
      client.close_issue(@repository.slug, issue_number)
    end

    redirect_to issues_repository_path(@repository, state: params[:state]),
                notice: "#{helpers.pluralize(issue_numbers.size, 'issue')} closed."
  rescue => e
    redirect_to issues_repository_path(@repository, state: params[:state]), alert: "Failed to close issues: #{e.message}"
  end
end
