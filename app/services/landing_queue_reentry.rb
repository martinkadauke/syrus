class LandingQueueReentry
  START_BLOCKER_PREFIX = "landing start blocked:".freeze

  Result = Data.define(:cleared_job_ids) do
    def any? = cleared_job_ids.any?
  end

  def self.call(job) = new(job).call
  def self.landing_start_blocker?(reason) = reason.to_s.start_with?(START_BLOCKER_PREFIX)

  def initialize(job)
    @job = job
  end

  def call
    ids = clearable_jobs.pluck(:id)
    if ids.any?
      Job.where(id: ids).update_all(landing_failure_reason: nil, updated_at: Time.current)
    end
    LandingQueueProcessorJob.perform_later
    Result.new(cleared_job_ids: ids)
  end

  private

  attr_reader :job

  def clearable_jobs
    scope = if AppSetting.merge_train_enabled? && job.epic_id.present?
      job.epic.jobs.where(state: "approved")
    else
      Job.where(id: job.id, state: "approved")
    end

    scope.where("landing_failure_reason LIKE ?", "#{START_BLOCKER_PREFIX}%")
  end
end
