module Workflows
  # Issue → PR.
  #
  #   prepare → loop(implement, grader_fanout, grader_collect) → summarize → pr_open
  #
  # prepare reads `.syrus.yml` (or auto-detects from lockfiles)
  # and runs deterministic setup like `bundle install` so the
  # agent doesn't burn turns watching deps download. implement
  # runs the agent end-to-end (multi-turn) on the prepared
  # workspace, makes commits, but does NOT call submit_summary
  # — that's a separate phase.
  #
  # grader_fanout reads `.syrus.yml` from the workspace and
  # materializes one `grader` Step per configured grader between
  # itself and grader_collect (dynamic chain insertion). Each
  # grader runs unconditionally — no short-circuit between graders
  # — so the agent's next iteration prompt has every failure to
  # work with. grader_collect aggregates: if any required grader
  # Step ended :failed, it fails (triggering the loop's next
  # iteration); otherwise it succeeds and the chain advances.
  #
  # summarize is a short claude call that --resumes implement's
  # session and asks the agent to call submit_summary; tokens are
  # essentially free because Anthropic's session reuse caches the
  # conversation server-side. pr_open is non-agentic — it reads
  # workflow.artifacts["pr_title"]/["pr_body"] and runs
  # PullRequestOpener.
  class Initial < Base
    steps :prepare,
          Workflows::Loop.new(steps: [ :implement, :grader_fanout, :grader_collect ]),
          :summarize,
          :pr_open

    def self.trigger_kind = "initial"

    def self.steps_for(job)
      chain = [
        "prepare",
        Workflows::Loop.new(
          max_iterations: AppSetting.grade_max_iterations,
          steps: [ :implement, :grader_fanout, :grader_collect ]
        ),
        "summarize",
        "pr_open"
      ]
      prepare_skipped_for?(job) ? chain.reject { |node| node == "prepare" } : chain
    end

    def self.prepare_skipped_for?(job)
      job.skip_prepare?
    end
  end
end
