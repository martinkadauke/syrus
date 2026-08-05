class JobManualPause
  def self.pause!(job, by_user:)
    job.pause_manually!(by_user: by_user)
  end

  def self.unpause!(job)
    job.unpause_manually!
    resume_active_workflows(job)
    LandingQueueProcessorJob.perform_later if job.approved? || job.landing?
  end

  def self.resume_active_workflows(job)
    job.workflows.where(state: %w[ queued running ]).find_each do |workflow|
      StepDispatcher.clear_start_blocked!(workflow, StepDispatcher::MANUAL_PAUSE_REASON)
      StepDispatcher.resume_deferred_phase(workflow.id)
    end
  end
end
