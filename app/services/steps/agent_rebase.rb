module Steps
  # Second step of Rebase workflow. Agentic: spawns claude with
  # Prompts::Rebase to resolve the conflicts that AutoRebase
  # couldn't. Short-circuits to a no-op if the upstream auto_rebase
  # step already cleanly rebased (nothing left to do).
  class AgentRebase < Base
    def call
      if workflow.artifact("auto_rebase_succeeded")
        log("agent_rebase: skipped — auto_rebase already succeeded")
        return
      end

      workspace.setup
      run.update!(prompt: compose_prompt) if run.prompt.blank?

      log("invoking agent for agent_rebase step (workflow ##{workflow.id})")
      pre_sha = head_sha
      run_agent(prompt: run.prompt)

      post_sha = head_sha
      raise StepFailed, "agent_rebase: agent didn't move HEAD (rebase aborted or no-op)" if pre_sha == post_sha

      log("agent_rebase: rebased #{pre_sha[0, 7]} → #{post_sha[0, 7]}")
      workflow.set_artifact!("agent_rebase_succeeded", true)
      run.update!(head_sha: post_sha)
    end

    private

    def compose_prompt
      pr_number = job.pr_number || job.external_pr_number
      Prompts::Rebase.new(
        repo_slug: repository.slug,
        branch_name: job.branch_name,
        base_branch: repository.default_branch,
        pr_number: pr_number
      ).to_s
    end
  end
end
