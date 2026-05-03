module Prompts
  # Prompt for `resume` Runs. claude --print --resume <id> reloads the
  # full prior conversation history but still requires a *new* prompt
  # argument — print mode's contract — and won't auto-continue if you
  # pass nothing meaningful. This is that prompt: tell claude what
  # just happened, what survived, and what to do.
  #
  # The submit_summary instructions block is appended via the same
  # mechanism the other primary prompts use, so the MCP contract
  # carries through.
  class Resume
    def to_s
      [ body, SubmitSummaryInstructions::TEXT ].join("\n\n")
    end

    private

    def body
      <<~PROMPT.strip
        Your previous session on this task was interrupted (the worker
        process died — most likely a deploy). The conversation history
        above is yours; pick up where you left off.

        Important: the working tree may have changed since then.

        - Syrus checked out the branch fresh from origin's HEAD before
          resuming you. Any **uncommitted** edits you had in flight at
          the moment of interruption are gone. Anything you'd already
          **committed** survived.
        - Run `git status` and `git log --oneline -10` to see the
          current state vs what you remember.
        - If a tool call you made just before the interruption appears
          to have not taken effect, redo just that step.

        Continue from where you were. Do not redo work that's already
        committed. Do not start over from scratch — the context above
        is the whole point of resuming.
      PROMPT
    end
  end
end
