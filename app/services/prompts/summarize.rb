module Prompts
  # Summarize-step prompt for the Initial / Retry workflows.
  # Spawned as a short claude call with `--resume <implement-step
  # session_id>`, so the agent has full context of the
  # implementation it just finished. Its only job is to call the
  # `submit_summary` MCP tool with title + body + summary.
  class Summarize
    def to_s
      <<~PROMPT.strip
        You just finished the **implement** step on a Syrus run. Your
        previous conversation (resumed above) contains the full
        context: the issue, the files you read, the changes you
        committed.

        Now produce the PR copy by calling the `submit_summary` MCP
        tool with three fields. If your tool list shows a prefixed MCP
        name, call the exact prefixed name shown there; do not call bare
        `submit_summary` unless that exact bare name is available.

        - `pr_title`: 50–72 chars, imperative mood ("Add greeting
          helper", not "Adds…" or "This PR adds…"). No leading
          prefix or repo slug.
        - `pr_body`: markdown, 1–3 short paragraphs. Lead with the
          why; then mention what changed. No headings, no "This
          PR…" preamble.
        - `summary`: 1–2 sentences, operator-facing, shown on the
          Syrus job page.

        Don't recap the whole conversation in your reply. Don't
        re-read files. Don't make additional commits — that phase
        is done. Just call the available `submit_summary` tool name and exit.
      PROMPT
    end
  end
end
