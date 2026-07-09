module Prompts
  # The instruction sent to GEMINI alongside the walkthrough video. Gemini's
  # job is extraction, not judgment: turn everything shown on screen and said
  # in the narration into a faithful, structured account that the chat agent
  # (which never sees the video) can act on. The response is constrained by
  # RESPONSE_SCHEMA — flat on purpose; deeply nested schemas get rejected.
  #
  # The schema is ordered the way a distilled multimodal model (Gemini Flash)
  # reasons best: transcript FIRST (Flash is excellent at timestamped ASR, and
  # a verbatim transcript anchors everything else and curbs hallucination),
  # THEN a topical segmentation (`sections` — the handles Syrus later uses to
  # re-analyze one range in detail), THEN issues grounded in both the
  # transcript and the visuals.
  class VideoWalkthroughAnalysis
    RESPONSE_SCHEMA = {
      type: "object",
      properties: {
        transcript: {
          type: "array",
          description: "The spoken narration, timestamped and verbatim-ish, in order.",
          items: {
            type: "object",
            properties: {
              timestamp: { type: "string", description: "mm:ss where this line of narration begins" },
              text: { type: "string", description: "what the user said, transcribed faithfully" }
            },
            required: %w[timestamp text]
          }
        },
        sections: {
          type: "array",
          description: "The session split into coherent topical segments — one screen, problem area, or task per section. These are the ranges a reviewer can zoom into later.",
          items: {
            type: "object",
            properties: {
              start: { type: "string", description: "mm:ss where the section begins" },
              end: { type: "string", description: "mm:ss where the section ends" },
              title: { type: "string", description: "short label for this segment" },
              summary: { type: "string", description: "1-2 sentences on what happens in this segment" }
            },
            required: %w[start end title summary]
          }
        },
        issues: {
          type: "array",
          description: "Every distinct problem, confusion, bug, glitch, or friction point, grounded in the transcript and the visuals.",
          items: {
            type: "object",
            properties: {
              timestamp: { type: "string", description: "mm:ss where the issue is most clearly visible or described" },
              title: { type: "string", description: "short imperative issue title" },
              description: { type: "string", description: "what happened, and what the user expected vs. what actually occurred" },
              severity: { type: "string", enum: %w[low medium high] },
              surface: { type: "string", description: "the UI area/screen/flow involved, as specifically as the video allows" },
              transcript_evidence: { type: "string", description: "the user's own words describing this issue, quoted from the narration — leave empty if they never mention it out loud" },
              visual_evidence: { type: "string", description: "what is visible on screen that shows the issue" },
              user_flagged: { type: "boolean", description: "true if the user explicitly pointed at this — a red pen mark / circle / underline on screen, or words like \"here\", \"this\", \"look at this\"" },
              needs_closer_look: { type: "boolean", description: "true when the detail matters but small text or fast on-screen action means a focused, full-resolution re-analysis of this moment would help" },
              unreadable_text: { type: "string", description: "When important on-screen text — an error code, ID, URL, config value, stack trace, precise number — is too small or too fleeting for you to read from the video WITH CONFIDENCE, do NOT guess it. Leave it out of the description, set needs_closer_look=true, and describe here exactly WHAT text must be read and WHERE on screen (e.g. \"the error code in the red-circled banner\", \"the value in the Timeout field, top-right\"). A downstream agent reads it from a high-resolution screenshot at this issue's timestamp. Leave empty when there is no such hard-to-read text." }
            },
            required: %w[title description severity]
          }
        },
        summary: {
          type: "string",
          description: "2-4 sentence plain-language overview: what app was tested, what the user did, overall impression"
        },
        open_questions: {
          type: "array",
          items: { type: "string" },
          description: "ambiguities the chat agent should ask the user about — where the video/narration was unclear or incomplete"
        }
      },
      required: %w[transcript summary issues open_questions]
    }.freeze

    def to_s
      <<~PROMPT
        This video is a screen recording of a person testing an application
        under active development, narrating as they go. The AUDIO NARRATION is
        your primary signal — it explains intent ("I expected this to...") that
        the screen alone doesn't show. Watch the screen AND listen closely.

        Work in this order:

        1. TRANSCRIBE the narration first. Produce `transcript` as timestamped
           (mm:ss), verbatim-ish lines, in order. This anchors everything else.

        2. SEGMENT the session into `sections` — coherent topical ranges, one
           screen / problem area / task each, with start and end timestamps
           (mm:ss), a short title, and a 1-2 sentence summary.

        3. EXTRACT `issues` — every distinct problem, confusion, bug, visual
           glitch, or friction point, whether shown, described, or both. For
           each issue:
           - Give the mm:ss where it is clearest.
           - Describe what happened and what the user expected.
           - Set `transcript_evidence` to the user's OWN WORDS about it, quoted
             from the narration (leave empty if they never say it aloud).
           - Set `visual_evidence` to what is visible on screen.
           - Judge `severity`: `high` (blocks the user / data loss / broken
             feature), `medium` (works but wrong or confusing), `low` (cosmetic,
             wording, spacing).
           - Name the `surface` (page, component, flow) as specifically as you can.
           - The user may MARK problems on screen with a red pen — a circle,
             underline, or arrow — or point with words like "here", "this",
             "look at this". Treat any such red mark or verbal pointer as a
             strong locator: set `user_flagged` to true for that issue.
           - Set `needs_closer_look` to true when the detail matters but small
             text or fast action means a focused, full-resolution re-analysis of
             that moment would read it more reliably.
           - You are analyzing VIDEO, and you frequently CANNOT reliably read
             small on-screen text — error codes, IDs, URLs, config values, stack
             traces, precise numbers. When such text is IMPORTANT to the issue,
             DO NOT GUESS it: a plausible-but-wrong error code or ID is worse than
             none. Instead set `needs_closer_look` to true and use
             `unreadable_text` to describe exactly WHAT text should be read and
             WHERE on screen (e.g. "the error code in the red-circled banner",
             "the value in the Timeout field, top-right"). A downstream agent will
             read the exact characters from a HIGH-RESOLUTION screenshot at that
             timestamp — so flag it, don't fabricate it.

        Do NOT invent issues, merge distinct issues, or editorialize about
        priorities. If something is ambiguous — you can't tell what the user
        meant, the screen was unreadable, a step happened off-screen — put a
        concrete question in `open_questions` rather than guessing.

        Respond with JSON only, matching the provided schema.
      PROMPT
    end
  end
end
