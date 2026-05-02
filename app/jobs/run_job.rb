class RunJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(job_id) {
    "repo:#{::Job.where(id: job_id).pick(:repository_id)}"
  }

  discard_on ActiveRecord::RecordNotFound

  class CancelledMidRun < StandardError; end

  def perform(job_id)
    @job = ::Job.find(job_id)
    return if @job.terminal?

    @job.start!
    log("starting job #{@job.id} for #{@job.repository.slug}##{@job.issue_number}")

    @workspace = JobWorkspace.new(@job, git: streaming_git)
    @workspace.setup
    @job.update!(branch_name: @workspace.branch_name)
    abort_if_cancelled!

    placeholder_commit
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

  def placeholder_commit
    marker = @workspace.path.join(".syrus-marker")
    File.write(marker, "job_id: #{@job.id}\nissue: #{@job.repository.slug}##{@job.issue_number}\n")
    git = streaming_git
    chdir = @workspace.path.to_s
    git.run("add", ".syrus-marker", chdir: chdir)
    git.run(
      "-c", "user.name=Syrus",
      "-c", "user.email=syrus@noreply.invalid",
      "commit", "-m", "Syrus placeholder for #{@job.repository.slug}##{@job.issue_number}",
      chdir: chdir
    )
  end

  def push_branch
    git = streaming_git(env: { "GIT_TERMINAL_PROMPT" => "0" })
    push_url = @job.repository.authenticated_push_url(@job.user.github_token)
    git.run("push", push_url, "HEAD:refs/heads/#{@workspace.branch_name}", chdir: @workspace.path.to_s)
  end

  def open_pull_request
    PullRequestOpener.new(@job.repository).open(
      branch: @workspace.branch_name,
      title: "[syrus] placeholder for ##{@job.issue_number}",
      body: "Opened by Syrus's deterministic harness as a placeholder for issue ##{@job.issue_number}. No agent involvement yet — M3 proves the plumbing; the real work lands in M4."
    )
  end

  def log(chunk)
    next_seq = (@job.job_logs.maximum(:sequence) || -1) + 1
    @job.job_logs.create!(chunk: chunk, sequence: next_seq)
  end
end
