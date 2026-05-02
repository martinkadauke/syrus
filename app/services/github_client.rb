class GithubClient
  USER_AGENT = "Syrus/0.1 (+https://github.com/tkadauke/syrus)".freeze

  def self.for(user)
    new(user)
  end

  def initialize(user)
    raise ArgumentError, "user must have a github_token" if user.github_token.blank?
    @user = user
    @client = Octokit::Client.new(
      access_token: user.github_token,
      user_agent: USER_AGENT,
      auto_paginate: true
    )
  end

  # Returns Sawyer::Resource enumerable. Includes pull_request items —
  # IngestPolicy filters those.
  def issues_with_label(repo_slug, label, state: "open")
    @client.list_issues(repo_slug, state: state, labels: label)
  rescue Octokit::TooManyRequests => e
    Rails.logger.warn("[GithubClient] #{@user.email_address} rate-limited on #{repo_slug}: #{e.message}")
    raise
  end

  def create_pull_request(repo_slug, base:, head:, title:, body:)
    @client.create_pull_request(repo_slug, base, head, title, body)
  rescue Octokit::TooManyRequests => e
    Rails.logger.warn("[GithubClient] #{@user.email_address} rate-limited on #{repo_slug}: #{e.message}")
    raise
  end
end
