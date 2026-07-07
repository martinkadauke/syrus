module Prompts
  # The instruction sent to GEMINI alongside the walkthrough video. Gemini's
  # job is extraction, not judgment: turn everything shown on screen and said
  # in the narration into a faithful, structured account that the chat agent
  # (which never sees the video) can act on. The response is constrained by
  # RESPONSE_SCHEMA — flat on purpose; deeply nested schemas get rejected.
  class VideoWalkthroughAnalysis
    RESPONSE_SCHEMA = {
      type: "object",
      properties: {
        summary: {
          type: "string",
          description: "2-4 sentence overview: what app was tested, what the user did, overall impression"
        },
        issues: {
          type: "array",
          items: {
            type: "object",
            properties: {
              timestamp: { type: "string", description: "mm:ss where the issue appears in the video" },
              title: { type: "string", description: "short imperative issue title" },
              detail: {
                type: "string",
                description: "what happened on screen, what the user said about it, expected vs actual"
              },
              severity: { type: "string", enum: %w[blocker major minor polish] },
              area: { type: "string", description: "the app surface involved (page, component, flow)" }
            },
            required: %w[title detail severity]
          }
        },
        positive_notes: {
          type: "array",
          items: { type: "string" },
          description: "things the user liked or that worked well, if any were mentioned"
        },
        open_questions: {
          type: "array",
          items: { type: "string" },
          description: "questions for the user where the video/narration was ambiguous or incomplete"
        }
      },
      required: %w[summary issues open_questions]
    }.freeze

    def to_s
      <<~PROMPT
        This video is a screen recording of a person testing an application
        that is under active development, narrating as they go. Your job is to
        extract a faithful, structured account of the session for the
        development team. Watch the screen AND listen to the narration — the
        narration often explains intent ("I expected this to...") that the
        screen alone doesn't show.

        Extract EVERY distinct problem, confusion, bug, visual glitch, or
        friction point — whether demonstrated on screen, described out loud,
        or both. For each issue:
        - Use the video timestamp (mm:ss) where it is most clearly visible.
        - Describe what actually happened AND what the user expected, when
          discernible.
        - Judge severity honestly: `blocker` (cannot proceed / data loss),
          `major` (feature doesn't work as intended), `minor` (works but
          wrong/awkward), `polish` (cosmetic, wording, spacing).
        - Name the app surface involved as specifically as the video allows.

        Do NOT invent issues, merge distinct issues, or editorialize about
        priorities. If the user says something positive, record it in
        positive_notes. If anything is ambiguous — you can't tell what the
        user meant, the screen was unreadable, a step happened off-screen —
        put a concrete question in open_questions rather than guessing.

        Respond with JSON only, matching the provided schema.
      PROMPT
    end
  end
end
