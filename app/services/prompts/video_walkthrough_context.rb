module Prompts
  # What the CHAT AGENT sees once Gemini has analyzed a walkthrough video.
  # Composed as the text of an injected user-role turn (delivered through the
  # queued-message machinery so it never collides with an in-flight turn).
  # The agent never sees the video — this rendering IS its entire knowledge
  # of the session, so it must be faithful and complete. The closing
  # instruction steers the agent to the existing follow-up-question / Epic
  # proposal behavior rather than inventing a new workflow.
  class VideoWalkthroughContext
    SEVERITY_ORDER = %w[blocker major minor polish].freeze

    def initialize(walkthrough:, user_note: nil, illustrated: false)
      @walkthrough = walkthrough
      @user_note = user_note
      @illustrated = illustrated
    end

    def to_s
      parts = []
      parts << header
      parts << "The user's note with the video: #{@user_note}" if @user_note.present?
      parts << "## Session summary\n#{@walkthrough.analysis_summary}"
      parts << issues_section
      parts << screenshots_note if @illustrated
      parts << positive_notes_section if positive_notes.any?
      parts << open_questions_section if @walkthrough.analysis_open_questions.any?
      parts << closing_instruction
      parts.compact.join("\n\n")
    end

    private

    def header
      duration = @walkthrough.duration_seconds
      length = duration ? " (#{duration / 60}m#{format('%02d', duration % 60)}s)" : ""
      <<~TEXT.strip
        I recorded a walkthrough video#{length} of me testing the app and had it
        analyzed. Below is the structured analysis of everything I showed and
        narrated.
      TEXT
    end

    def issues_section
      issues = @walkthrough.analysis_issues
      return "## Issues found\n(none — the walkthrough surfaced no problems)" if issues.empty?

      sorted = issues.sort_by { |issue| SEVERITY_ORDER.index(issue["severity"].to_s) || SEVERITY_ORDER.length }
      lines = sorted.map do |issue|
        timestamp = issue["timestamp"].presence
        area = issue["area"].presence
        meta = [ issue["severity"], area, timestamp && "at #{timestamp}" ].compact.join(", ")
        "- **#{issue['title']}** (#{meta})\n  #{issue['detail']}"
      end
      "## Issues found (#{issues.size})\n#{lines.join("\n")}"
    end

    def screenshots_note
      <<~TEXT.strip
        I've attached a screenshot for each issue above, captured from the
        video at the issue's timestamp (each is named "walkthrough <time> —
        <issue>"). Use them to see exactly what I saw, and reference the
        relevant screenshot when you scope the fix.
      TEXT
    end

    def positive_notes
      Array(@walkthrough.analysis&.dig("positive_notes"))
    end

    def positive_notes_section
      "## What worked well\n#{positive_notes.map { |note| "- #{note}" }.join("\n")}"
    end

    def open_questions_section
      questions = @walkthrough.analysis_open_questions
      <<~TEXT.strip
        ## Open questions from the analysis
        The video analysis flagged these ambiguities:
        #{questions.map { |q| "- #{q}" }.join("\n")}
      TEXT
    end

    def closing_instruction
      <<~TEXT.strip
        Please help me turn this into actionable work. If the open questions
        above (or anything else) materially change how the work should be
        scoped, ask me — briefly, all at once. Otherwise, propose an Epic that
        groups these issues into well-scoped Jobs, using your normal proposal
        flow. Skip anything too vague to act on and say so.
      TEXT
    end
  end
end
