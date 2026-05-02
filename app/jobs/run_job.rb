class RunJob < ApplicationJob
  queue_as :default

  # One Run at a time per repository — the agent serializes per branch
  # by way of the per-repo lock since Job has at most one branch open.
  limits_concurrency to: 1, key: ->(run_id) {
    "repo:#{::Run.where(id: run_id).joins(:job).pick('jobs.repository_id')}"
  }

  discard_on ActiveRecord::RecordNotFound

  class CancelledMidRun < StandardError; end
  class AgentRunFailed < StandardError; end

  # Test seam — let specs swap in a fake runner without exec'ing claude.
  class << self
    attr_accessor :agent_runner
  end

  def perform(run_id)
    @run = ::Run.find(run_id)
    @job = @run.job
    return if @run.terminal?
    return if @job.closed?

    @run.start!
    @run.save!  # AASM after-callbacks set started_at; persist it.
    @job.update!(started_at: Time.current) if @job.started_at.nil?

    log("starting #{@run.trigger_kind} run #{@run.id} for #{@job.repository.slug}##{@job.issue_number}")

    @workspace = JobWorkspace.new(@run, git: streaming_git)
    @workspace.setup
    # Persist whenever it differs — covers initial-run setup AND the
    # recovery case where a previous initial died before pushing,
    # leaving a stale Job.branch_name without an origin counterpart.
    @job.update!(branch_name: @workspace.branch_name) if @job.branch_name != @workspace.branch_name
    abort_if_cancelled!

    run_agent_and_commit
    abort_if_cancelled!

    push_branch
    abort_if_cancelled!

    open_pull_request_if_missing

    @run.succeed!
    @run.save!
    log("run complete — #{@run.initial? ? "PR ##{@job.pr_number} opened" : "follow-up commit pushed"}")
  rescue CancelledMidRun
    log("cancelled mid-run")
  rescue StandardError => e
    log("FAIL: #{e.class}: #{e.message}")
    if @run&.may_fail?
      @run.fail!
      @run.save!
    end
    raise
  ensure
    @workspace&.cleanup
  end

  private

  def abort_if_cancelled!
    raise CancelledMidRun if @run.reload.cancelled? || @job.reload.closed?
  end

  def streaming_git(env: {})
    GitRunner.new(log_sink: ->(line) { log(line.chomp) }, env: env)
  end

  def run_agent_and_commit
    prompt = @run.prompt.presence || compose_initial_prompt
    @run.update!(prompt: prompt) if @run.prompt.blank?

    log("invoking agent for #{@job.repository.slug}##{@job.issue_number} (run #{@run.id}, trigger=#{@run.trigger_kind})")
    result = AgentInvocation.new(
      @workspace.path,
      prompt: prompt,
      oauth_token: @job.user.claude_oauth_token,
      log_sink: ->(chunk) { log(chunk) },
      runner: self.class.agent_runner
    ).run

    persist_agent_metadata(result)

    raise AgentRunFailed, "agent timed out" if result.timed_out
    raise AgentRunFailed, "agent reported #{result.outcome || 'error'}" if result.is_error
    raise AgentRunFailed, "agent exited #{result.exit_status}" unless result.success?

    commit_agent_changes
    diff = capture_diff_against_default

    raise AgentRunFailed, "agent produced no changes" if diff.blank?

    @run.update!(agent_diff: diff, head_sha: head_sha)
  end

  # Initial runs get the issue title + body via Prompts::Initial.
  # Follow-up runs (pr_comment, ci_failure, ...) arrive with @run.prompt
  # already composed by whatever job created them — we use it as-is.
  def compose_initial_prompt
    issue = GithubClient.for(@job.user).fetch_issue(@job.repository.slug, @job.issue_number)
    Prompts::Initial.new(issue: issue).to_s
  end

  def persist_agent_metadata(result)
    updates = {}
    updates[:agent_turns] = result.turns if result.turns
    updates[:agent_outcome] = result.outcome if result.outcome
    @run.update!(updates) if updates.any?
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
      "commit", "-m", commit_message,
      chdir: chdir
    )
  end

  def commit_message
    if @run.initial?
      "Syrus agent for #{@job.repository.slug}##{@job.issue_number}"
    else
      "Syrus #{@run.trigger_kind} for #{@job.repository.slug}##{@job.issue_number}"
    end
  end

  # Three-dot diff (`main...HEAD`) — the same view GitHub's "Files
  # changed" tab shows. It's `git diff $(merge-base main HEAD) HEAD`,
  # so it captures only what *this branch* contributed since it
  # diverged from default. Two-dot (`main..HEAD`) would also include
  # commits that landed on main after the branch was opened, rendered
  # as spurious "deletions" — which made follow-up Run diffs look
  # gigantic when main moved forward.
  def capture_diff_against_default
    base = @job.repository.default_branch
    GitRunner.new.run("diff", "#{base}...HEAD", chdir: @workspace.path.to_s)
  end

  def head_sha
    GitRunner.new.run("rev-parse", "HEAD", chdir: @workspace.path.to_s).strip
  end

  def push_branch
    git = streaming_git(env: { "GIT_TERMINAL_PROMPT" => "0" })
    push_url = @job.repository.authenticated_push_url(@job.user.github_token)
    git.run("push", push_url, "HEAD:refs/heads/#{@workspace.branch_name}", chdir: @workspace.path.to_s)
  end

  # Open a PR whenever the Job doesn't have one yet, regardless of which
  # Run is doing the pushing. Most often that's the initial Run, but if
  # an initial Run died before pushing and a replay Run took over and
  # succeeded, the replay needs to open the PR too — otherwise we end up
  # with a branch on origin and no PR pointing at it.
  def open_pull_request_if_missing
    return if @job.pr_number.present?
    pr_number = PullRequestOpener.new(@job.repository).open(
      branch: @workspace.branch_name,
      title: "[syrus] #{@job.repository.slug}##{@job.issue_number}",
      body: "Opened by Syrus from issue ##{@job.issue_number}. Run took #{@run.agent_turns || '?'} turn(s) (#{@run.trigger_kind}).\n\nReview the diff carefully — this PR was authored by an LLM."
    )
    @job.update!(pr_number: pr_number)
  end

  def log(chunk)
    next_seq = (@run.job_logs.maximum(:sequence) || -1) + 1
    @run.job_logs.create!(chunk: chunk, sequence: next_seq)
  end
end
