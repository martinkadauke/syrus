module Steps
  class AutoMerge < Base
    include AutoMergeControl

    TRANSIENT_MERGE_ERRORS = [
      Octokit::Conflict,
      Octokit::ServiceUnavailable,
      Octokit::InternalServerError
    ].freeze
    REBASE_MERGE_REJECTED_ERROR = /(?:can(?:not|'t)|could not) be rebased/i

    def call
      client = GithubClient.for(repository: repository, user: job.user)

      if waiting_for_parent_merge?
        queue_until_parent_merges!
        return
      end

      gate = AutoMergeGate.new(job: job, client: client, bypass_cache: true).evaluate
      persist_github_mergeability(gate.pr)

      # Every early-exit path here must transition the Job out of
      # :landing before cancelling the workflow — otherwise
      # LandingQueueProcessor keeps treating that repository as
      # occupied. defer_landing preserves the approval and sends the
      # Job back to :approved so it re-enters the landing queue after
      # the blocker clears; the :closed case closes the Job to match
      # the PR.
      case gate.outcome
      when :closed
        log("auto_merge: PR ##{job.pr_number} is already closed; cancelling workflow", kind: "system")
        job.close_with_reason!("pr_closed") if job.open?
        cancel_workflow!
        return
      when :transient
        log("auto_merge: deferred - mergeable_state=#{deferred_mergeable_state(gate)}", kind: "system")
        defer_landing_if_possible!
        cancel_workflow!
        return
      when :needs_rebase
        handle_needs_rebase!(gate, client: client)
        return
      end

      raise StepFailed, "auto_merge: #{gate.reason}" unless gate.merge_ready?

      merge = merge_pull_request(client, gate)
      return unless merge

      raise StepFailed, "auto_merge: GitHub did not report the PR as merged" unless merge.respond_to?(:merged) ? merge.merged : merge[:merged]

      comment = "Merged automatically by Syrus after approval and green checks. Job ##{job.id}: #{job_url}"
      client.add_issue_comment(repository.slug, job.pr_number, comment)
      job.close_with_reason!("pr_merged") if job.open?
      log("auto_merge: merged PR ##{job.pr_number}")
    end

    private

    def merge_pull_request(client, gate)
      client.merge_pull_request(
        repository.slug,
        job.pr_number,
        commit_title: "Merge #{repository.slug}##{job.pr_number} via Syrus",
        merge_method: "rebase"
      )
    rescue Octokit::MethodNotAllowed => e
      if rebase_merge_rejected?(e)
        handle_rebase_merge_rejection!(gate, e, client: client)
        nil
      elsif retryable_method_not_allowed?(e)
        defer_after_transient_merge_error!(e)
        nil
      else
        raise StepFailed, "auto_merge: GitHub merge failed: #{e.message}"
      end
    rescue *TRANSIENT_MERGE_ERRORS => e
      defer_after_transient_merge_error!(e)
      nil
    rescue Octokit::Error => e
      raise StepFailed, "auto_merge: GitHub merge failed: #{e.message}"
    end

    def defer_after_transient_merge_error!(error)
      log("auto_merge: deferred - #{transient_error_message(error)}", kind: "system")
      job.defer_landing! if job.may_defer_landing?
      job.save! if job.changed?
      cancel_workflow!
    end

    def retryable_method_not_allowed?(error)
      !rebase_merge_rejected?(error)
    end

    def rebase_merge_rejected?(error)
      REBASE_MERGE_REJECTED_ERROR.match?(error.message.to_s)
    end

    def handle_rebase_merge_rejection!(gate, error, client:)
      reason = "GitHub rejected rebase merge: #{transient_error_message(error)}"
      rebase_gate = AutoMergeGate::Result.new(
        outcome: :needs_rebase,
        approved: gate.approved?,
        reason: reason,
        pr: gate.pr
      )
      handle_needs_rebase!(rebase_gate, defer_reason: reason, client: client)
    end

    def transient_error_message(error)
      error.message.to_s[0, 121]
    end

    def waiting_for_parent_merge?
      parent = job.parent_job
      return false unless parent

      !(parent.closed? && parent.closure_reason == "pr_merged")
    end

    def queue_until_parent_merges!
      parent = job.parent_job
      workflow.set_artifact!("pending_auto_merge", "waiting_for_parent")
      log("auto_merge: waiting for parent ##{parent.pr_number || parent.id} to merge; queued auto-merge will re-evaluate after stack rebase", kind: "system")
      cancel_workflow!
    end

    def job_url
      Rails.application.routes.url_helpers.job_url(
        job,
        host: ENV.fetch("SYRUS_APP_HOST", "localhost")
      )
    rescue StandardError
      "job #{job.id}"
    end
  end
end
