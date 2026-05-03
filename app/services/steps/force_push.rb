module Steps
  # Final step of Rebase workflow. Non-agentic. Force-pushes the
  # rebased branch to origin. Skipped if auto_rebase already
  # pushed (AutoRebase service does its own push when clean).
  class ForcePush < Base
    def call
      if workflow.artifact("auto_rebase_succeeded")
        log("force_push: skipped — auto_rebase already pushed")
        return
      end

      workspace.setup
      log("force_push: pushing rebased #{workspace.branch_name} (workflow ##{workflow.id})")

      git = streaming_git(env: { "GIT_TERMINAL_PROMPT" => "0" })
      push_url = repository.authenticated_push_url(job.user.github_token)
      git.run("push", "--force", push_url,
              "HEAD:refs/heads/#{workspace.branch_name}",
              chdir: workspace.path.to_s)
    end
  end
end
