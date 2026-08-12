module Prompts
  # Fallback summarize prompt for the rare case where resuming the
  # implementation session overflows the provider context. It gives the
  # agent bounded job context and the produced diff, then asks it to call
  # the same submit_summary MCP tool as the normal resumed summarize step.
  class SummarizeFallback
    MAX_BODY_BYTES = 16 * 1024
    MAX_DIFF_BYTES = Prompts::PullRequestSummary::MAX_DIFF_BYTES

    def initialize(issue:, diff:)
      @issue = issue
      @diff = diff.to_s
    end

    def to_s
      <<~PROMPT.strip
        You just finished the implementation for this Syrus job, but the
        original agent session was too large to resume. Use this bounded
        context instead.

        Produce the PR copy by calling the `submit_summary` MCP tool with
        three fields. If your tool list shows a prefixed MCP name, call the
        exact prefixed name shown there; do not call bare `submit_summary`
        unless that exact bare name is available.

        - `pr_title`: 50-72 chars, imperative mood ("Add greeting helper",
          not "Adds..." or "This PR adds..."). No leading prefix or repo slug.
        - `pr_body`: markdown, 1-3 short paragraphs. Lead with the why; then
          mention what changed. No headings, no "This PR..." preamble.
        - `summary`: 1-2 sentences, operator-facing, shown on the Syrus job page.

        Do not edit files, run commands, or make commits. Just call the
        available `submit_summary` tool name and exit.

        # Original job
        Title: #{@issue.title}

        Body:
        #{trimmed_body}

        # Implementation diff
        ```diff
        #{trimmed_diff}
        ```
      PROMPT
    end

    private

    def trimmed_body
      body = @issue.body.to_s.strip
      return "(empty)" if body.blank?
      return body if body.bytesize <= MAX_BODY_BYTES

      "#{body.safe_byteslice(0, MAX_BODY_BYTES)}\n...[truncated, #{body.bytesize - MAX_BODY_BYTES} more bytes]"
    end

    def trimmed_diff
      return "(empty)" if @diff.blank?
      return @diff if @diff.bytesize <= MAX_DIFF_BYTES

      "#{@diff.safe_byteslice(0, MAX_DIFF_BYTES)}\n...[truncated, #{@diff.bytesize - MAX_DIFF_BYTES} more bytes]"
    end
  end
end
