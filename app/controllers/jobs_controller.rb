class JobsController < ApplicationController
  before_action :load_job

  def show
  end

  # Soft replay — push another commit to the existing branch by spawning
  # a new Run on the same Job. Useful when the agent stopped halfway
  # through and you want it to take another swing without abandoning the
  # in-flight work.
  def run_again
    if @job.closed?
      redirect_to job_path(@job), alert: "Thread is closed — use Start over to begin a new one."
      return
    end

    if @job.any_active_run?
      redirect_to job_path(@job), alert: "A Run is already in progress — wait for it to finish."
      return
    end

    @job.runs.create!(trigger_kind: "replay")
    redirect_to job_path(@job), notice: "Run enqueued."
  end

  # Hard reset — close this thread (no more polling, no more runs), then
  # open a fresh Job for the same issue. The new Job clones, creates a
  # new branch, and opens a new PR. The old branch + PR are abandoned
  # but left untouched on GitHub.
  def restart
    @job.cancel_active_runs_and_close!("replaced") if @job.open?
    new_job = Current.user.jobs.create!(
      repository: @job.repository,
      issue_number: @job.issue_number
    )
    redirect_to job_path(new_job), notice: "Started over — new branch and PR will be created."
  end

  def cancel
    if @job.closed?
      redirect_to job_path(@job), alert: "Job is already closed."
      return
    end

    @job.cancel_active_runs_and_close!("cancelled")
    redirect_to job_path(@job), notice: "Cancellation requested."
  end

  # Manually fire PollPullRequestJob for this Job — useful when the
  # operator just left a review comment and doesn't want to wait for
  # the 5-min recurring schedule.
  def poll_feedback
    unless @job.open? && @job.pr_number.present?
      redirect_to job_path(@job), alert: "Can only check feedback on open Jobs that have a PR."
      return
    end

    PollPullRequestJob.perform_later(@job.id)
    redirect_to job_path(@job), notice: "Checking PR feedback now…"
  end

  # Manually enqueue a rebase Run on this Job's PR. Same trigger the
  # auto-rebase poller uses, just operator-initiated when they don't
  # want to wait for the next 15-min sweep. Refuses to stack rebases
  # or rebase a Job with no PR. Skips the closed-Job guard since rebase
  # Runs are independent of Job lifecycle (preempted Job's external PR
  # can still need rebases).
  def rebase
    unless @job.pr_number.present? || @job.external_pr_number.present?
      redirect_to job_path(@job), alert: "No PR on this Job to rebase."
      return
    end

    if @job.runs.where(trigger_kind: "rebase").active.exists?
      redirect_to job_path(@job), alert: "A rebase is already in progress — wait for it to finish."
      return
    end

    @job.runs.create!(trigger_kind: "rebase")
    redirect_to job_path(@job), notice: "Rebase enqueued."
  end

  # Undo a close. The next poll cycle may immediately re-close the
  # Job if the underlying reason still applies (e.g. syrus-stop label
  # still on the PR, PR merged on GitHub) — that's intentional. Local
  # state catches up to GitHub state via the next poll.
  def reopen
    unless @job.may_reopen?
      redirect_to job_path(@job), alert: "Job isn't closed."
      return
    end

    prior_reason = @job.closure_reason
    @job.reopen!
    @job.save!
    redirect_to job_path(@job), notice: reopen_notice(prior_reason)
  end

  private

  def reopen_notice(prior_reason)
    base = "Thread reopened."
    case prior_reason
    when "syrus_stop"
      "#{base} Heads up: the next poll will re-close it if the syrus-stop label is still on the PR."
    when "pr_merged", "pr_closed"
      "#{base} Heads up: the next poll will check the PR state and may re-close it."
    else
      base
    end
  end

  def load_job
    @job = Current.user.jobs.includes(:repository, runs: :job_logs).find(params[:id])
  end
end
