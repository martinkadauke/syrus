module Prompts
  # What the CHAT AGENT sees once Gemini has analyzed a walkthrough video.
  # Composed as the text of an injected user-role turn (delivered through the
  # queued-message machinery so it never collides with an in-flight turn).
  # The agent never sees the video — this rendering IS its entire knowledge
  # of the session, so it must be faithful and complete. The closing
  # instruction steers the agent to the existing follow-up-question / Epic
  # proposal behavior rather than inventing a new workflow.
  class VideoWalkthroughContext
    # High → low. Matches the analysis schema's severity enum.
    SEVERITY_ORDER = %w[high medium low].freeze

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
      parts << sections_section if sections.any?
      parts << issues_section
      parts << screenshots_note if @illustrated
      parts << closer_look_note if closer_look_issues.any?
      parts << transcript_section if transcript.any?
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

    def sections
      @sections ||= @walkthrough.analysis_sections
    end

    def sections_section
      lines = sections.map do |section|
        range = [ section["start"].presence, section["end"].presence ].compact.join("–")
        range = range.present? ? " (#{range})" : ""
        summary = section["summary"].presence
        "- **#{section['title']}**#{range}#{summary ? " — #{summary}" : ''}"
      end
      "## Sections\n#{lines.join("\n")}"
    end

    def issues_section
      issues = @walkthrough.analysis_issues
      return "## Issues found\n(none — the walkthrough surfaced no problems)" if issues.empty?

      sorted = issues.sort_by { |issue| SEVERITY_ORDER.index(issue["severity"].to_s) || SEVERITY_ORDER.length }
      "## Issues found (#{issues.size})\n#{sorted.map { |issue| render_issue(issue) }.join("\n")}"
    end

    def render_issue(issue)
      timestamp = issue["timestamp"].presence
      surface = issue["surface"].presence
      flags = []
      flags << "user-flagged" if issue["user_flagged"]
      flags << "needs a closer look" if issue["needs_closer_look"]
      meta = [ issue["severity"], surface, timestamp && "at #{timestamp}", *flags ].compact.join(", ")

      lines = [ "- **#{issue['title']}** (#{meta})" ]
      lines << "  #{issue['description']}" if issue["description"].present?
      lines << "  The user said: \"#{issue['transcript_evidence']}\"" if issue["transcript_evidence"].present?
      lines << "  On screen: #{issue['visual_evidence']}" if issue["visual_evidence"].present?
      lines.join("\n")
    end

    def screenshots_note
      <<~TEXT.strip
        I've attached a screenshot for each issue above, captured from the
        video at the issue's timestamp (each is named "walkthrough <time> —
        <issue>"). Use them to see exactly what I saw, and reference the
        relevant screenshot when you scope the fix.
      TEXT
    end

    def closer_look_issues
      @closer_look_issues ||= @walkthrough.analysis_issues.select { |issue| issue["needs_closer_look"] }
    end

    # Point the agent at the "zoom in" capability for the moments the analysis
    # itself flagged as hard to read at first pass (small text, fast action).
    def closer_look_note
      titles = closer_look_issues.filter_map { |issue| issue["title"].presence }.first(5)
      <<~TEXT.strip
        Some issues are marked "needs a closer look"#{titles.any? ? " (e.g. #{titles.map { |t| "\"#{t}\"" }.join(', ')})" : ''}:
        the detail matters but small text or fast on-screen action may have been
        hard to read at first pass. If getting the exact wording, error text, or
        the precise click sequence would materially sharpen the work, use the
        `analyze_walkthrough_segment` tool (walkthrough ##{@walkthrough.id}) to
        re-examine just that time range at full resolution before you scope it.
      TEXT
    end

    def transcript
      @transcript ||= @walkthrough.analysis_transcript
    end

    def transcript_section
      lines = transcript.filter_map do |line|
        text = line["text"].presence
        next unless text

        stamp = line["timestamp"].presence
        stamp ? "[#{stamp}] #{text}" : text
      end
      return nil if lines.empty?

      "## Narration transcript\n#{lines.join("\n")}"
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
