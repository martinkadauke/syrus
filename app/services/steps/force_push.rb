module Steps
  # Final step of Rebase workflow. Non-agentic. Force-pushes the
  # rebased branch to origin.
  #
  # Note: only runs when reached. AutoRebase calls
  # cancel_downstream! on a clean rebase (it already pushed), so
  # the dispatcher advances past this step in that case and we
  # never get here.
  class ForcePush < Base
    def call
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
