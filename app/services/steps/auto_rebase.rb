module Steps
  # First step of Rebase workflow. Non-agentic: invokes the
  # AutoRebase service (deterministic `git rebase origin/<base>`).
  # On success the deterministic rebase already pushed; nothing
  # left for AgentRebase or ForcePush to do, so this step cancels
  # the downstream chain. The dispatcher walks past cancelled
  # steps and terminates the workflow as succeeded.
  #
  # On conflict, lets the chain proceed to AgentRebase.
  class AutoRebase < Base
    def call
      if pull_request_merged?
        log("auto_rebase: pull request already merged; stopping rebase workflow")
        cancel_downstream!(reason: "pull request already merged")
        return
      end

      log("auto_rebase: attempting deterministic rebase (workflow ##{workflow.id})")
      result = ::AutoRebase.new(job).call

      if result.succeeded?
        log("auto_rebase: clean — #{result.note}")
        cancel_downstream!(reason: "auto_rebase already succeeded; nothing left to do")
      else
        workflow.set_artifact!("auto_rebase_reason", result.reason)
        log("auto_rebase: #{result.reason} — falling through to agent_rebase")
      end
    end

    private

    def pull_request_merged?
      pr_number = job.pr_number || job.external_pr_number
      return false if pr_number.blank?

      pr = GithubClient.for(job.user).pull_request(repository.slug, pr_number, bypass_cache: true)
      pr.merged == true
    end
  end
end
