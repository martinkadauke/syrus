class ScheduledTaskFire
  Result = Data.define(:job, :skipped, :reason) do
    def fired? = !skipped
  end

  def initialize(task, now: Time.current)
    @task = task
    @now = now
  end

  # Spawn a cron Job for this fire (or skip per pr_pileup_policy).
  # Stamps last_fired_at unconditionally so the next due-check uses
  # this tick as its baseline. Marks one_shot tasks as `fired` after
  # they spawn their Job. Honors pr_pileup_policy:
  #
  #   skip     — don't fire if a prior PR is still open
  #   pile     — fire regardless (lets PRs stack)
  #   replace  — close prior open PRs from this task before firing
  def call
    case @task.pr_pileup_policy
    when "skip"
      if @task.has_open_pr?
        @task.record_fire!(at: @now)
        return Result.new(job: nil, skipped: true, reason: "prior_pr_open")
      end
    when "replace"
      close_prior_open_prs
    when "pile"
      # fall through
    end

    rendered_prompt = Prompts::ScheduledTask.new(scheduled_task: @task, fired_at: @now).to_s

    job = Job.create!(
      user: @task.user,
      repository: @task.repository,
      kind: "cron",
      scheduled_task: @task,
      issue_number: nil
    )
    # Cron Jobs still use the legacy single-Run path until commit 7
    # migrates Job's initial-run entry point too. Pre-rendered prompt
    # gets carried through on Run.prompt; legacy RunJob.perform reads
    # it directly.
    job.runs.create!(trigger_kind: "initial", prompt: rendered_prompt)

    @task.record_fire!(at: @now)
    @task.mark_fired_one_shot! if @task.one_shot?

    Result.new(job: job, skipped: false, reason: nil)
  end

  private

  def close_prior_open_prs
    @task.open_pr_jobs.find_each do |old_job|
      Rails.logger.info("[ScheduledTaskFire] task ##{@task.id} closing prior PR ##{old_job.pr_number} (job ##{old_job.id}) per replace policy")
      begin
        GithubClient.for(@task.user).close_pull_request(@task.repository.slug, old_job.pr_number)
      rescue StandardError => e
        Rails.logger.warn("[ScheduledTaskFire] failed to close PR ##{old_job.pr_number}: #{e.class}: #{e.message}")
      end
      old_job.close_with_reason!("replaced_by_scheduled_task")
    end
  end
end
