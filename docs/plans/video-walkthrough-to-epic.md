# Video walkthrough → Epic

A user records (or drags in) a narrated screen recording of themselves testing
the app under development. Syrus uploads it, has Gemini extract a structured
account of every issue shown/narrated, injects that into the chat, and the
chat agent asks follow-ups or proposes an Epic — using the proposal machinery
that already exists.

## Design principles

1. **Gemini is the eyes, the chat agent stays the brain.** Gemini never talks
   to the user directly. Its output (issue list + walkthrough summary +
   uncertainty notes) is injected into the chat turn, and the *existing* chat
   agent — which already knows how to ask follow-up questions and propose
   Epics/Jobs via the proposal tools — takes it from there. Zero new
   proposal/question plumbing; one new context source.
2. **Recording must feel native.** `getDisplayMedia` (the Meet-style picker)
   in the browser; `setDisplayMediaRequestHandler` (+ macOS system picker /
   TCC guidance) in the desktop app. Gentle, *visible* gating: a countdown
   ring toward the max duration, not a hard error at the end.
3. **Gemini setup is optional until the moment it isn't.** Dragging a video or
   choosing "Record a walkthrough" with no Gemini configured opens the setup
   sheet inline — same animated staged-validation experience as the Claude
   credential flow — and returns the user to what they were doing.

## The pipeline

```
[record | drag | pick]                          (browser/desktop)
   → client-side gate: duration (video.duration / recorder clock), size
   → upload (real upload — NOT the base64-inline path images use)
   → ChatVideoWalkthrough row + Active Storage blob   (Rails)
   → VideoWalkthroughAnalysisJob                       (SolidQueue, `chat` queue?)
       → Gemini Files API upload → poll ACTIVE
       → generateContent(model: <research>, responseSchema: issues+summary+questions)
       → persist analysis on the row
   → inject into chat as a turn: "The user attached a walkthrough video…"
       + structured analysis; AppUserChannel streams progress states
   → chat agent (Claude/Codex) reads it, asks follow-ups or proposes the Epic
```

Progress states surfaced in the chat UI on the attachment card:
`uploading → analyzing (Gemini) → ready | failed(reason, retry)`.

## Established facts (firsthand recon)

- **Chat composer** (`app/frontend/routes/Chat.tsx` ~2500): `+` button opens
  an attachment popover ("Upload file" + AddAttachment for repos/epics/jobs/
  docs). File input currently `image/*,application/pdf`, base64-inlined —
  fine for images, wrong for video. "Record a walkthrough" is a new popover
  item; video becomes a proper upload.
- **Active Storage is live**: `Document` (polymorphic `attachable`,
  `has_one_attached :file`, 20MB cap, content-type whitelist) +
  `local_volume`/minio services. Videos get their own model — the Document
  caps/whitelist stay untouched.
- **Epic proposals**: `ChatEpicProposalMaterializer` + proposal states —
  reused as-is via the chat agent.
- **Credential pattern**: `/api/v1/app/credentials/*` — `test_credential`,
  `test_github_token`, `claude_oauth_start/exchange`, `codex_oauth_exchange`,
  each returning `CredentialTestPayload`. Gemini follows the same shape.
  Encrypted storage: `User#claude_oauth_token` pattern → `User#gemini_api_key`
  (or oauth blob, per research).
- **Chat providers** (`ChatProviders::Base`) accept `image_paths`/`file_paths`
  — analysis text injects into the prompt; keyframes could ride as images
  later (not v1).
- **Desktop**: no display-media handler exists yet; windows use the default
  session. Handler + macOS TCC detection to add in `main.ts`.
- **ffmpeg IS in the runtime image** (added for frame extraction) — but
  duration gating still happens client-side
  (`HTMLVideoElement.duration` for dragged files; the recorder's own clock
  while recording). Server re-validates only byte size. Gemini decodes video
  itself.
- **i18n**: chat strings live in `app/frontend/i18n/locales/{en,de,la}/chat.json`
  — all new UI copy needs all three.

## Research verdicts (2026-current, cited in the research transcript)

**Model: `gemini-3.5-flash`** — GA since May 2026, free-tier eligible, native
video+audio (the narration track is ingested!), structured outputs
(`responseSchema`), 1M context. WebM is a supported video format, so
MediaRecorder output uploads **without transcoding**. Video ≈ 300 tokens/sec
at default `media_resolution`, ≈ 100 at `low`. Use `media_resolution: low`
for recordings ≥ 12 min (screen content at 1 fps survives it fine, and it
keeps 15-min videos inside free-tier TPM).

**Files API** — resumable upload to
`upload/v1beta/files`, 2 GB/file, 20 GB/project, 48 h retention, **free in
all tiers**; poll `files.get` until `state == ACTIVE` before generateContent.

**Auth: API key ONLY — the OAuth hope doesn't survive contact with the
facts.** Two independent killers: (1) *technical* — the gemini-cli OAuth
token authenticates to the Code Assist API (`cloudcode-pa.googleapis.com`),
which has **no Files API** and degraded multimodal support; server-side video
upload only exists on `generativelanguage.googleapis.com` with an API key.
(2) *policy* — reusing gemini-cli's first-party OAuth client in a third-party
app is an actively-enforced ToS violation in 2026 (real account suspensions,
cascading to users' whole Google accounts). The consolation: an AI Studio key
(aistudio.google.com/apikey) is **free, no card**, and validates with a free
`models.list` ping — so the onboarding is a paste-and-verify flow, which
Syrus already does well.

**Gating numbers** (free tier realistic):
- Max duration **15:00** — countdown ring in the recorder, warn at 14:00,
  friendly hard stop at 15:00; dragged files gated by `video.duration`.
- Max size **500 MB** (2 GB is the hard API cap; 500 keeps uploads snappy;
  our recorder profile yields ~20 MB/min → 15 min ≈ 300 MB).
- Don't hardcode RPM/RPD — Google serves per-project live limits now.
  Surface 429s gracefully ("Gemini's free-tier quota is busy — try again in
  a minute, or enable billing on your AI Studio project").
- Cost note for the paid tier: ~$0.03–0.30 input per video. Trivial.

**Recorder profile** — `getDisplayMedia` (Chrome's Meet-style picker) video
capped 1920×1080 @ 10–15 fps + `getUserMedia` mic (echoCancellation +
noiseSuppression), combined into one MediaStream; MediaRecorder
`video/webm;codecs=vp9,opus` (probe fallbacks vp8 → webm → mp4),
2.5 Mbps video + 128 kbps audio.

**Desktop** — `session.setDisplayMediaRequestHandler`: `useSystemPicker` on
macOS (Electron 33+, native SCContentSharingPicker); custom
`desktopCapturer` source picker on Windows/fallback. macOS TCC: the FIRST
capture attempt triggers the OS dialog and itself fails (black frames); the
grant requires an app **relaunch**. So: preflight
`systemPreferences.getMediaAccessStatus("screen")` before recording, and on
`denied`/`not-determined` show guidance + deep-link to Settings + a Relaunch
button. Windows: no permission needed.

## Final architecture

**Data:** `ChatVideoWalkthrough` — belongs_to chat_session + user,
`has_one_attached :file`, states `uploaded → analyzing → analyzed | failed`,
`duration_seconds`, `byte_size`, `gemini_file_uri`, `analysis` (JSON: summary,
issues[{timestamp,title,detail,severity,area}], open_questions[]),
`error_message`. `User#gemini_api_key` — `encrypts`, same pattern as
`codex_api_key`.

**Upload:** new multipart endpoint
`POST /api/v1/app/chats/:id/video_walkthroughs` (NOT the base64 message
path — videos are 100–500 MB). Server validates content type
(webm/mp4/quicktime) + size; duration comes from the client (no ffmpeg in the
image; Gemini decodes the video itself).

**Analysis:** `VideoWalkthroughAnalysisJob` (queue: `default` — keeps the
low-concurrency `chat` queue free for turns): Gemini Files upload → poll
ACTIVE → one `generateContent` with `responseSchema` → persist → broadcast
progress via `AppEvents` at every transition.

**Chat injection:** the user's message (their text + the video chip) sends
immediately. When analysis completes, Syrus enqueues the analysis as the next
turn (the queued-message machinery already serializes turns): a user-role
message carrying `Prompts::VideoWalkthroughContext` — the structured issues +
summary + Gemini's open questions — with explicit instruction that the agent
should ask the user follow-ups if needed and otherwise propose an Epic via
the normal proposal tools. **The existing agent does the Epic proposing.**

**Gemini setup gate:** dragging a video / picking "Record a walkthrough"
without a key opens `GeminiSetupSheet` (mirrors ConfigureAgentModal): paste
key → staged animated validation (format check → live `models.list` ping →
"video-capable model available" check) → save → return to what you were
doing. Also a permanent section on /credentials.

## Naming

Composer popover item: **"Record a walkthrough"**. Attachment card:
"Walkthrough video". No feature flag — the Gemini gate is the gate.

## Build order

A. Backend foundation: migrations, model, `Gemini::Client`, credential
   endpoints + validation, specs.
B. Upload endpoint + analysis job + chat turn injection, specs.
C. Frontend: composer integration (drag/pick/record), recorder HUD with
   countdown gating, GeminiSetupSheet, progress card states, vitest.
D. Desktop: display-media handler + macOS TCC preflight/relaunch, pins.
E. Docs (website + CLAUDE.md), full suites, local image + DMG for install.

