class PollRepositoryJob < ApplicationJob
  queue_as :default

  def perform(repository_id, force: false)
    repository = Repository.find_by(id: repository_id)
    return unless repository
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

    if existing_active_job?(repository, issue.number)
      Rails.logger.info("[PollRepositoryJob] #{repository.slug}##{issue.number} dedup: active Job already exists")
      return
    end

    Job.create!(
      user: repository.user,
      repository: repository,
      issue_number: issue.number
    )
  end

  def existing_active_job?(repository, issue_number)
    Job.active.exists?(repository_id: repository.id, issue_number: issue_number)
  end
end
