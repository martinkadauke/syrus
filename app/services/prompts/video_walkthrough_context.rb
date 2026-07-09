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

    def initialize(walkthrough:, user_note: nil, illustrated: false, attached_issue_keys: [])
      @walkthrough = walkthrough
      @user_note = user_note
      @illustrated = illustrated
      @attached_issue_keys = Array(attached_issue_keys)
    end

    # Stable identity for matching an analysis issue to an attached screenshot.
    # The analysis job builds these keys from the frames it ACTUALLY extracted
    # (frame.seconds + frame.label == the issue's parsed timestamp + title), and
    # this class computes the same key per issue to decide attached-vs-not. The
    # two must stay in sync — change both if you change the shape.
    def self.attachment_key(seconds:, title:)
      [ seconds, title.to_s ]
    end

    def to_s
      parts = []
      parts << header
      parts << "The user's note with the video: #{@user_note}" if @user_note.present?
      parts << "## Session summary\n#{@walkthrough.analysis_summary}"
      parts << sections_section if sections.any?
      parts << issues_section
      parts << screenshots_note if @illustrated
      parts << read_attached_screenshots_note if attached_reads.any?
      parts << fetch_on_demand_note if unattached_reads.any?
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
      lines << unreadable_line(issue) if issue["unreadable_text"].present?
      lines.join("\n")
    end

    # Per-issue steering for hard-to-read on-screen text. ONLY promise a
    # screenshot when THIS issue's frame was actually attached to the turn;
    # otherwise point the agent at the on-demand tool so we never tell it to
    # read a still that was never attached (text-only delivery, extraction
    # failure, or a frame dropped past the per-video cap).
    def unreadable_line(issue)
      want = issue["unreadable_text"].to_s.strip
      if attached?(issue)
        "  Too small to read from the video — read the exact text off the attached screenshot: #{want}"
      else
        "  Too small to read from the video, and no screenshot is attached — use " \
          "#{read_frame_call(issue)} to grab a high-resolution still, then read: #{want}"
      end
    end

    # The on-demand fetch call the agent can run to grab a crisp still itself.
    def read_frame_call(issue)
      stamp = issue["timestamp"].presence || "mm:ss"
      "read_walkthrough_frame(walkthrough_id: #{@walkthrough.id}, timestamp: #{stamp})"
    end

    # Did this issue's screenshot actually make it into the turn? Keyed on the
    # same (parsed seconds, title) identity the analysis job builds from the
    # frames it extracted.
    def attached?(issue)
      key = self.class.attachment_key(
        seconds: Gemini::FrameExtractor.parse_timestamp(issue["timestamp"]),
        title: issue["title"]
      )
      @attached_issue_keys.include?(key)
    end

    def screenshots_note
      <<~TEXT.strip
        I've attached a screenshot for each issue above, captured from the
        video at the issue's timestamp (each is named "walkthrough <time> —
        <issue>"). Use them to see exactly what I saw, and reference the
        relevant screenshot when you scope the fix.
      TEXT
    end

    # Issues with a specific hard-to-read value the video model flagged for a
    # screenshot read (`unreadable_text`). These drive the OCR handoff, split by
    # whether a crisp screenshot for the moment actually reached this turn. (The
    # broader `needs_closer_look` signal is handled separately by closer_look_note,
    # which points at the full re-analysis tool.)
    def unreadable_text_issues
      @unreadable_text_issues ||= @walkthrough.analysis_issues.select do |issue|
        issue["unreadable_text"].to_s.strip.present?
      end
    end

    def attached_reads
      @attached_reads ||= unreadable_text_issues.select { |issue| attached?(issue) }
    end

    def unattached_reads
      @unattached_reads ||= unreadable_text_issues.reject { |issue| attached?(issue) }
    end

    # OCR handoff for issues whose crisp screenshot IS attached to this turn: the
    # video model can't reliably read small on-screen text, but the CHAT AGENT
    # (Claude) reads a crisp still perfectly. Steer it to READ the exact text off
    # the attached screenshot rather than trust the model's (deliberately
    # withheld) guess. Always carries the never-invent guard.
    def read_attached_screenshots_note
      <<~TEXT.strip
        ## Read the exact text off the screenshots
        Some on-screen text — error codes, IDs, URLs, config values, exact
        numbers, stack traces — was too small or too fleeting for the video model
        to read reliably, so it deliberately did NOT transcribe it. The CRISP
        SCREENSHOTS attached above capture those exact moments, and you read still
        images far better than the video model reads video. READ the precise text
        directly from the relevant screenshot and use the EXACT value in the Epic.
        NEVER invent, guess, autocomplete, or paraphrase a value you cannot read;
        if a screenshot still isn't legible, say so and grab a fresh
        high-resolution still with read_walkthrough_frame(walkthrough_id:
        #{@walkthrough.id}, timestamp: <mm:ss>) rather than guessing.#{read_list(attached_reads)}
      TEXT
    end

    # OCR handoff for flagged text with NO attached screenshot — a text-only
    # turn (no ffmpeg / extraction failure), or a frame dropped past the
    # per-video cap. Turn the miss into a graceful fallback: fetch a crisp still
    # on demand and read it. Always carries the never-invent guard.
    def fetch_on_demand_note
      <<~TEXT.strip
        ## Fetch and read these screenshots on demand
        Some on-screen text was too small for the video model to read, and NO
        screenshot is attached for these moments. Grab a high-resolution still
        yourself with read_walkthrough_frame(walkthrough_id: #{@walkthrough.id},
        timestamp: <mm:ss>) and read the exact text off it. NEVER invent, guess,
        autocomplete, or paraphrase a value you cannot read; if you truly cannot
        read it, say so.

        Fetch and read:
        #{unattached_reads.filter_map { |issue| fetch_line(issue) }.join("\n")}
      TEXT
    end

    def read_list(issues)
      asks = issues.filter_map { |issue| ask_line(issue) }
      asks.any? ? "\n\nSpecifically, read:\n#{asks.join("\n")}" : ""
    end

    def ask_line(issue)
      want = issue["unreadable_text"].to_s.strip
      return if want.blank?

      stamp = issue["timestamp"].presence
      title = issue["title"].to_s.strip
      "- #{[ stamp && "at #{stamp}", title.presence ].compact.join(' ')}#{stamp || title.present? ? ' — ' : ''}#{want}"
    end

    def fetch_line(issue)
      want = issue["unreadable_text"].to_s.strip
      stamp = issue["timestamp"].presence
      title = issue["title"].to_s.strip
      label = [ stamp && "at #{stamp}", title.presence ].compact.join(" ")
      prefix = label.present? ? "#{label} — " : ""
      "- #{prefix}#{want} (#{read_frame_call(issue)})"
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
