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

  private

  def load_job
    @job = Current.user.jobs.includes(:repository, runs: :job_logs).find(params[:id])
  end
end
