module Workflows
  # Issue → PR.
  #
  #   prepare → implement → summarize → pr_open
  #
  # prepare reads `.syrus.yml` (or auto-detects from lockfiles)
  # and runs deterministic setup like `bundle install` so the
  # agent doesn't burn turns watching deps download. implement
  # runs the agent end-to-end (multi-turn) on the prepared
  # workspace, makes commits, but does NOT call submit_summary
  # — that's a separate phase. summarize is a short claude call
  # that --resumes implement's session and asks the agent to call
  # submit_summary; tokens are essentially free because Anthropic's
  # session reuse caches the conversation server-side. pr_open is
  # non-agentic — it reads workflow.artifacts["pr_title"]/["pr_body"]
  # and runs PullRequestOpener.
  class Initial < Base
    steps :prepare, :implement, :summarize, :pr_open

    def self.trigger_kind = "initial"
  end
end
