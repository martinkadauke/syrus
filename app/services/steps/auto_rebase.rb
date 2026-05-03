module Steps
  # First step of Rebase workflow. Non-agentic: invokes the
  # AutoRebase service (deterministic `git rebase origin/<base>`).
  # If it succeeds, the workflow is effectively done — there's
  # nothing for agent_rebase to do, and force_push has nothing
  # new to push (the deterministic rebase already pushed). The
  # handler signals downstream skipping by stamping a workflow
  # artifact `auto_rebase_succeeded: true` that AgentRebase /
  # ForcePush check.
  #
  # If AutoRebase reports `conflict`, this step still succeeds
  # (it ran to completion) and the chain advances to AgentRebase.
  class AutoRebase < Base
    def call
      log("auto_rebase: attempting deterministic rebase (workflow ##{workflow.id})")
      result = ::AutoRebase.new(job).call

      if result.succeeded?
        workflow.set_artifact!("auto_rebase_succeeded", true)
        log("auto_rebase: clean — #{result.note} (downstream steps will short-circuit)")
      else
        workflow.set_artifact!("auto_rebase_succeeded", false)
        workflow.set_artifact!("auto_rebase_reason", result.reason)
        log("auto_rebase: #{result.reason} — falling through to agent_rebase")
      end
    end
  end
end
