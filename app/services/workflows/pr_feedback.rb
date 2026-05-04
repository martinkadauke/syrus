module Workflows
  # Reviewer left a comment on the PR. Address it on the existing
  # branch, push.
  #
  #   respond → summarize_amend → push
  #
  # respond runs the agent with the comment text + diff context —
  # *fresh* claude session (no --resume from the prior workflow's
  # implement; cross-workflow resume gets unwieldy and the prompt
  # already carries the context the agent needs). summarize_amend
  # --resumes respond and produces the *commit message for the
  # amendment* (not a fresh PR title). push is non-agentic.
  class PrFeedback < Base
    steps :prepare, :respond, :summarize_amend, :push

    def self.trigger_kind = "pr_comment"
  end
end
