class RunJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(job_id) {
    "repo:#{::Job.where(id: job_id).pick(:repository_id)}"
  }

  discard_on ActiveRecord::RecordNotFound

  class CancelledMidRun < StandardError; end
  class AgentRunFailed < StandardError; end

  # Test seam — let specs swap in a fake runner without exec'ing claude.
  class << self
    attr_accessor :agent_runner
  end

  def perform(job_id)
    @job = ::Job.find(job_id)
    return if @job.terminal?

    @job.start!
    log("starting job #{@job.id} for #{@job.repository.slug}##{@job.issue_number}")

    @workspace = JobWorkspace.new(@job, git: streaming_git)
    @workspace.setup
    @job.update!(branch_name: @workspace.branch_name)
    abort_if_cancelled!

    run_agent_and_commit
    abort_if_cancelled!

    push_branch
    abort_if_cancelled!

    pr_number = open_pull_request
    @job.update!(pr_number: pr_number)

    @job.succeed!
    log("PR ##{pr_number} opened — job complete")
  rescue CancelledMidRun
    log("cancelled mid-run")
  rescue StandardError => e
    log("FAIL: #{e.class}: #{e.message}")
    @job&.fail! if @job&.may_fail?
    raise
  ensure
    @workspace&.cleanup
  end

  private

  def abort_if_cancelled!
    raise CancelledMidRun if @job.reload.cancelled?
  end

  def streaming_git(env: {})
    GitRunner.new(log_sink: ->(line) { log(line.chomp) }, env: env)
  end

  def run_agent_and_commit
    issue = GithubClient.for(@job.user).fetch_issue(@job.repository.slug, @job.issue_number)
    prompt = "#{issue.title}\n\n#{issue.body}".strip

    log("invoking agent for #{@job.repository.slug}##{@job.issue_number}")
    result = AgentInvocation.new(
      @workspace.path,
      prompt: prompt,
      api_key: @job.user.claude_api_key,
      log_sink: ->(chunk) { log(chunk) },
      runner: self.class.agent_runner
    ).run

    @job.update!(agent_turns: result.turns) if result.turns

    raise AgentRunFailed, "agent timed out" if result.timed_out
    raise AgentRunFailed, "agent exited #{result.exit_status}" unless result.success?

    commit_agent_changes
    diff = capture_diff_against_default

    raise AgentRunFailed, "agent produced no changes" if diff.blank?

    @job.update!(agent_diff: diff)
  end

  def commit_agent_changes
    chdir = @workspace.path.to_s
    git = streaming_git
    status = git.run("status", "--porcelain", chdir: chdir)
    return if status.strip.empty?

    git.run("add", "-A", chdir: chdir)
    git.run(
      "-c", "user.name=Syrus",
      "-c", "user.email=syrus@noreply.invalid",
      "commit", "-m", "Syrus agent for #{@job.repository.slug}##{@job.issue_number}",
      chdir: chdir
    )
  end

  def capture_diff_against_default
    base = @job.repository.default_branch
    GitRunner.new.run("diff", "#{base}..HEAD", chdir: @workspace.path.to_s)
  end

  def push_branch
    git = streaming_git(env: { "GIT_TERMINAL_PROMPT" => "0" })
    push_url = @job.repository.authenticated_push_url(@job.user.github_token)
    git.run("push", push_url, "HEAD:refs/heads/#{@workspace.branch_name}", chdir: @workspace.path.to_s)
  end

  def open_pull_request
    PullRequestOpener.new(@job.repository).open(
      branch: @workspace.branch_name,
      title: "[syrus] #{@job.repository.slug}##{@job.issue_number}",
      body: "Opened by Syrus from issue ##{@job.issue_number}. Agent ran for #{@job.agent_turns || '?'} turn(s).\n\nReview the diff below — this PR was authored by an LLM and merits a careful read."
    )
  end

  def log(chunk)
    next_seq = (@job.job_logs.maximum(:sequence) || -1) + 1
    @job.job_logs.create!(chunk: chunk, sequence: next_seq)
  end
end
