module Prompts
  # Prompt for the first Run on a Job — just the issue title + body. The
  # agent has nothing else to go on yet (no prior commits, no reviewer
  # feedback). M0+ baseline; richer initial-prompt scaffolding can grow
  # here once we have data from real runs about where the agent gets
  # stuck.
  class Initial
    def initialize(issue:, epic: nil)
      @issue = issue
      @epic = epic
    end

    def to_s
      [ "#{@issue.title}\n\n#{@issue.body}".strip,
        epic_context,
        GitSafety::TEXT,
        SubmitSummaryInstructions::TEXT ].compact_blank.join("\n\n")
    end

    private

    def epic_context
      Prompts::EpicContext.new(epic: @epic).to_s
    end
  end
end
