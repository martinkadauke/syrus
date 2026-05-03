module Steps
  # Second step of Initial / Replay workflows. Short claude call
  # (--resumed against the implement step's session) whose only
  # job is to call `submit_summary` via the MCP sidecar. The
  # MCP tool writes pr_title / pr_body / summary onto the Run;
  # this handler then promotes them onto Workflow.artifacts so
  # downstream steps (and future workflow rounds) can read them.
  #
  # Also rewrites the implement step's placeholder commit message
  # to use the agent-authored pr_title — keeping the GH commit
  # log human-readable.
  class Summarize < Base
    SUMMARIZE_TURN_BUDGET = 5  # short prompt, no exploration needed

    def call
      workspace.setup
      run.update!(prompt: Prompts::Summarize.new.to_s) if run.prompt.blank?

      log("invoking agent for summarize step (workflow ##{workflow.id}, --resume from implement)")

      run_agent(prompt: run.prompt, max_turns: SUMMARIZE_TURN_BUDGET)

      promote_artifacts!
      rewrite_implement_commit_message!
    end

    private

    def promote_artifacts!
      run.reload  # MCP sidecar writes here mid-run
      raise StepFailed, "agent didn't call submit_summary" if run.agent_pr_title.blank?

      workflow.set_artifact!("pr_title", run.agent_pr_title) if run.agent_pr_title.present?
      workflow.set_artifact!("pr_body",  run.agent_pr_body)  if run.agent_pr_body.present?
      workflow.set_artifact!("summary",  run.agent_summary)  if run.agent_summary.present?
    end

    # Replace the implement step's placeholder commit message
    # ("Syrus implement step (will be rewritten by summarize)")
    # with the agent-authored pr_title, so the eventual GitHub
    # commit log shows useful subjects.
    def rewrite_implement_commit_message!
      title = workflow.artifact("pr_title")
      return if title.blank?
      streaming_git.run(
        "-c", "user.name=Syrus",
        "-c", "user.email=syrus@noreply.invalid",
        "commit", "--amend", "-m", title,
        chdir: workspace.path.to_s
      )
    end
  end
end
