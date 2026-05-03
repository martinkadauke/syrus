module Workflows
  # CI checks went red on the PR's branch. Diagnose, fix, push.
  #
  #   analyze_and_fix → summarize_amend → push
  #
  # Same shape as PrFeedback structurally; differs in the prompt
  # (Prompts::CiFailure carries the failing-checks payload). The
  # implement phase here is "look at the failing checks, find the
  # root cause, fix the code or the test".
  class CiFailure < Base
    steps :analyze_and_fix, :summarize_amend, :push

    def self.trigger_kind = "ci_failure"
  end
end
