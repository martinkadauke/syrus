require "base64"
require "tempfile"

# The video→Epic pipeline's middle: take an uploaded ChatVideoWalkthrough,
# run it through Gemini (Files API upload → poll ACTIVE → one structured
# generateContent), persist the analysis, and inject it into the chat as a
# queued user-role turn so the chat agent — the thing that already knows how
# to ask follow-ups and propose Epics — takes over.
#
# Media pipeline: the uploaded video is downloaded once to a local file used
# for the whole flow — Gemini analysis, then CRISP screenshots from that
# source, then a transcode to a compact 720p mp4 that REPLACES the stored blob.
# So the durable artifact is small (empirically, Gemini analyzes the 720p mp4
# as well as the original — the narration carries the context), while the
# screenshots came from the full-resolution source. Every media step is
# best-effort: a transcode failure keeps the original; a frame failure ships
# the turn text-only.
#
# Runs on the dedicated low-concurrency `videos` queue (config/queue.yml):
# a single analysis can pin a thread for many minutes (500MB streamed upload,
# ACTIVE polling, long generateContent), which would starve the pollers,
# reapers, and app-event broadcasts on `default`.
#
# Failure contract: NOTHING may strand a walkthrough in "analyzing" — every
# exit path either marks it analyzed or failed (the retry endpoint only
# accepts failed rows, and the chat chip spins until a terminal broadcast).
class VideoWalkthroughAnalysisJob < ApplicationJob
  queue_as :videos

  # Test seam, mirroring RunJob.agent_runner: specs swap in a fake client
  # factory instead of stubbing Net::HTTP.
  class << self
    attr_writer :client_factory

    def client_factory
      @client_factory ||= ->(api_key:) { Gemini::Client.new(api_key: api_key) }
    end
  end

  def perform(walkthrough_id)
    walkthrough = ChatVideoWalkthrough.find_by(id: walkthrough_id)
    return unless walkthrough&.uploaded?

    user = walkthrough.user
    unless user.gemini_configured?
      fail_walkthrough!(walkthrough, "Gemini is not configured — add an API key under Credentials.")
      return
    end

    transition!(walkthrough, "analyzing")

    # A retried walkthrough whose Gemini analysis already succeeded (the
    # earlier failure was in chat delivery) skips Gemini entirely — the
    # 48h Files-API retention makes re-analysis wasteful and re-upload the
    # only alternative.
    if walkthrough.analysis.blank?
      client = self.class.client_factory.call(api_key: user.gemini_api_key)
      # Resolve the model against what this key's project actually exposes —
      # the same VIDEO_MODELS list validation used, so a key that validated
      # green against a fallback model analyzes with it instead of 404ing.
      client.resolve_video_model!
      process_video(client, walkthrough)
    end

    # Deliver the chat turn BEFORE broadcasting success. If delivery raises,
    # deliver_chat_turn marks the row failed and returns false — broadcasting
    # "analyzed" first would clear the frontend chip and make the subsequent
    # "failed" event a no-op (the chip is already gone), hiding the failure.
    return unless deliver_chat_turn(walkthrough)

    walkthrough.update!(state: "analyzed", analyzed_at: Time.current, error_message: nil)
    broadcast(walkthrough)
  rescue Gemini::Client::AuthError => error
    fail_walkthrough!(walkthrough, "Gemini rejected the API key: #{error.message} Check it under Credentials.")
  rescue Gemini::Client::RateLimited
    fail_walkthrough!(
      walkthrough,
      "Gemini's quota is busy right now (free-tier limits are per-minute). Retry the analysis in a minute or two, or enable billing on your AI Studio project."
    )
  rescue Gemini::Client::ConnectionError
    fail_walkthrough!(walkthrough, "Could not reach Gemini — check the connection and retry the analysis.")
  rescue Gemini::Client::Error => error
    fail_walkthrough!(walkthrough, error.message)
  rescue StandardError => error
    # Catch-all so no exception class (Active Storage, DB, anything) can
    # strand the walkthrough in "analyzing" with a forever-spinning chip.
    Rails.logger.error("[VideoWalkthroughAnalysisJob] #{error.class}: #{error.message}")
    fail_walkthrough!(walkthrough, "The analysis hit an unexpected error (#{error.class}). Retry it.")
  end

  private

  # Download the video ONCE to a local file and run the whole media flow off
  # it: Gemini analysis, crisp screenshots from that source, then a transcode
  # to a compact mp4 that replaces the stored blob. @screenshot_attachments is
  # captured here (from the full-res source) for deliver_chat_turn.
  def process_video(client, walkthrough)
    with_local_video(walkthrough) do |video_path|
      walkthrough.update!(analysis: analyze(client, walkthrough, video_path))
      # Initial analysis: extract from the crisp pre-transcode source, so flagged
      # OCR frames get the higher-resolution capture.
      @screenshot_attachments = build_frame_attachments(walkthrough, video_path, crisp_source: true)
      compact_for_storage(walkthrough, video_path)
    end
  end

  # Yield a local path to the attachment's bytes, cleaned up afterward. The
  # copy is independent of the Active Storage record, so swapping the stored
  # blob (transcode) mid-flow is safe.
  def with_local_video(walkthrough)
    ext = File.extname(walkthrough.file.filename.to_s).presence || ".webm"
    tmp = Tempfile.new(["walkthrough", ext], binmode: true)
    walkthrough.file.download { |chunk| tmp.write(chunk) }
    tmp.flush
    yield tmp.path
  ensure
    tmp&.close!
  end

  def analyze(client, walkthrough, video_path)
    file = upload_to_gemini(client, walkthrough, video_path)
    active = client.wait_until_active(file.fetch("name"))
    # Record the mime of what we UPLOADED (content_type here is still the
    # pre-transcode original — compact_for_storage runs later), so the segment
    # "zoom in" path re-references the retained file with the right mimeType even
    # after the stored blob is transcoded to mp4.
    walkthrough.update!(
      gemini_file_uri: active["uri"],
      gemini_file_active_at: Time.current,
      gemini_file_content_type: walkthrough.content_type
    )

    generate(client, walkthrough, active.fetch("uri"), media_resolution: :default)
  rescue Gemini::Client::RateLimited
    # Graceful degradation: a long video at full resolution can blow the
    # free-tier per-minute token window. Rather than fail outright, retry
    # once at LOW resolution — worse small-text fidelity, but a working
    # analysis instead of none. Short videos never hit this, and a genuine
    # transient quota blip just re-fails (surfaced with the retry message).
    # Only retry the GENERATE phase at low res — and only when the upload
    # actually completed (gemini_file_uri persisted). A rate limit during
    # upload/poll has no file to re-generate against, so it just propagates.
    raise unless walkthrough.duration_seconds.to_i >= Gemini::Client::LOW_RESOLUTION_FALLBACK_SECONDS
    raise if walkthrough.gemini_file_uri.blank?

    Rails.logger.info("[VideoWalkthroughAnalysisJob] full-res rate-limited on a #{walkthrough.duration_seconds}s video; retrying at low resolution")
    generate(client, walkthrough, walkthrough.gemini_file_uri, media_resolution: :low)
  end

  def generate(client, walkthrough, file_uri, media_resolution:)
    client.generate_content(
      file_uri: file_uri,
      mime_type: walkthrough.content_type,
      prompt: Prompts::VideoWalkthroughAnalysis.new(repo_context: repo_context_for(walkthrough)).to_s,
      response_schema: Prompts::VideoWalkthroughAnalysis::RESPONSE_SCHEMA,
      media_resolution: media_resolution
    )
  end

  # Orient Gemini to WHICH app it's watching so it can name UI surfaces and read
  # intent precisely (the chat scopes the walkthrough to a repository). Kept to
  # cheap, already-loaded signal — the repo slug and the operator's pinned chat
  # context — so no GitHub fetch or checkout is needed on the videos queue. nil
  # for an unscoped chat, which the prompt handles by omitting the section.
  def repo_context_for(walkthrough)
    chat = walkthrough.chat_session
    parts = []
    repo = chat.repository
    parts << "Repository: #{repo.slug}" if repo
    if chat.pinned_context.present?
      parts << "Context the operator pinned to this chat:\n#{chat.pinned_context.to_s.strip}"
    end
    parts.join("\n\n").presence
  end

  def upload_to_gemini(client, walkthrough, video_path)
    # Stream the local copy to Gemini's resumable upload — the video is
    # already compressed (VP9 webm from the recorder, or the user's mp4), and
    # testing confirmed Gemini analyzes it as well as any transcode, so it
    # goes as-is with no pre-upload processing delay.
    File.open(video_path, "rb") do |io|
      client.upload_file(
        io: io,
        byte_size: File.size(video_path),
        content_type: walkthrough.content_type,
        display_name: walkthrough.display_title
      )
    end
  end

  # Replace the stored original with a compact 720p mp4 (transcode), so the
  # durable artifact is small. Best-effort: no ffmpeg / a transcode failure
  # keeps the original video. Runs AFTER screenshots (which used the crisp
  # source) so nothing downstream needs the higher resolution.
  def compact_for_storage(walkthrough, source_path)
    return unless Gemini::VideoTranscoder.available?

    Dir.mktmpdir("syrus-transcode-") do |dir|
      mp4 = File.join(dir, "compact.mp4")
      return unless Gemini::VideoTranscoder.to_compact_mp4(input_path: source_path, output_path: mp4)

      base = File.basename(walkthrough.file.filename.to_s, ".*").presence || "walkthrough"
      # The blob we're about to replace. has_one_attached is dependent: :purge,
      # which purges only on record DESTROY, NOT on replace — so without an
      # explicit purge the original (crisp) blob + its physical file orphan
      # forever, uncounted by the size budget. Capture it before the swap.
      previous_blob = walkthrough.file.blob

      # Upload the mp4 to a standalone blob OUTSIDE any transaction: attaching a
      # raw io inside a transaction defers the physical upload to after_commit,
      # by which point the tempfile/io is gone (FileNotFoundError). With the
      # blob already uploaded, the swap is a pure DB association we CAN wrap in a
      # transaction so a mid-swap failure can't leave the row's content_type/
      # byte_size describing the old webm while the stored blob is the new mp4.
      new_blob = File.open(mp4, "rb") do |io|
        ActiveStorage::Blob.create_and_upload!(io: io, filename: "#{base}.mp4", content_type: "video/mp4")
      end

      ActiveRecord::Base.transaction do
        walkthrough.file.attach(new_blob)
        walkthrough.update!(content_type: "video/mp4", byte_size: new_blob.byte_size)
      end

      # Only after the swap commits, and never the blob the row now points at.
      previous_blob.purge_later if previous_blob && previous_blob.id != new_blob.id
    end
  rescue StandardError => error
    Rails.logger.warn("[VideoWalkthroughAnalysisJob] storage transcode failed (keeping original): #{error.class}: #{error.message}")
  end

  # Inject the analysis as a queued chat turn. Returns true once the message
  # is queued (whether or not the promoter delivers it immediately — a busy
  # agent legitimately defers it). Returns false and marks the row failed if
  # queueing itself raises, so the analysis isn't reported as success when
  # its turn never reached the chat; retry re-delivers without re-analyzing.
  def deliver_chat_turn(walkthrough)
    chat = walkthrough.chat_session
    # Screenshots captured from the crisp source during process_video. On the
    # re-delivery path (analysis already present, process_video skipped),
    # re-extract from whatever video is still stored. Both build paths set
    # @attached_issue_keys to the issues that actually got a frame, so the
    # context can render per-issue "read the attached screenshot" vs
    # "fetch it on demand" truthfully.
    attachments = @screenshot_attachments || reextract_frame_attachments(walkthrough)
    text = Prompts::VideoWalkthroughContext.new(
      walkthrough: walkthrough, user_note: walkthrough.note,
      illustrated: attachments.any?, attached_issue_keys: @attached_issue_keys || []
    ).to_s
    content = { "text" => text, "video_walkthrough_id" => walkthrough.id }
    content["attachments"] = attachments if attachments.any?
    chat.queued_messages.create!(content: content)
    # Delivers immediately when the agent is idle; otherwise ChatTurnJob's
    # turn-end promotion picks it up — either way, no turn collision.
    ChatQueuedMessagePromoter.deliver_one_if_idle!(chat)
    true
  rescue StandardError => error
    Rails.logger.error("[VideoWalkthroughAnalysisJob] chat delivery failed: #{error.class}: #{error.message}")
    fail_walkthrough!(
      walkthrough,
      "The analysis succeeded but posting it to the chat failed. Retry to post it (the video won't be re-analyzed)."
    )
    false
  end

  # Grab one screen frame per issue (at Gemini's timestamp) from the given local
  # video, so the chat agent SEES each problem and the UI shows it. Issues the
  # video model FLAGGED as hard to read (needs_closer_look, or an explicit
  # unreadable_text note) are the ones the agent will OCR, so they're captured at
  # HIGHER resolution and top JPEG quality and are prioritized to survive the
  # per-video frame cap. Best-effort: any failure (no ffmpeg, bad timestamp)
  # yields no attachments and the turn ships text-only. Frames become base64
  # image attachments, the same shape chat already uses for pasted screenshots.
  def build_frame_attachments(walkthrough, video_path, crisp_source: true)
    @attached_issue_keys = []
    timestamps = frame_timestamps(walkthrough, crisp_source: crisp_source)
    return [] if timestamps.empty?

    frames = Gemini::FrameExtractor.extract(video_path: video_path, timestamps: timestamps)
    # Record which issues actually got a frame so the context renders each
    # issue's OCR steering ("read the attached screenshot" vs "fetch on demand")
    # from reality, not from the analysis list.
    @attached_issue_keys = frames.map do |frame|
      Prompts::VideoWalkthroughContext.attachment_key(seconds: frame.seconds, title: frame.label)
    end
    frames.map do |frame|
      clock = format("%d:%02d", frame.seconds / 60, frame.seconds % 60)
      { "name" => "walkthrough #{clock} — #{frame.label}".strip, "mime_type" => "image/jpeg",
        "data" => Base64.strict_encode64(frame.jpeg) }
    end
  rescue StandardError => error
    Rails.logger.warn("[VideoWalkthroughAnalysisJob] frame extraction failed: #{error.class}: #{error.message}")
    @attached_issue_keys = []
    []
  end

  # Build the extractor timestamp entries — one per issue with a parseable
  # timestamp — tagging each flagged issue with the higher OCR-grade resolution,
  # then selecting so every flagged issue gets a frame even if the total exceeds
  # the frame cap (issue order preserved within the selection).
  #
  # The high OCR-grade width only pays off when extracting from the CRISP
  # pre-transcode source (initial analysis). On the re-delivery path the only
  # source is the compact ~720p mp4, so requesting 1920 would just upscale
  # 1280→1920 — a bigger JPEG with zero added legibility. There, flagged issues
  # stay prioritized (so they survive the cap) but capture at the compact default
  # width. Flagged frames keep top JPEG quality either way (it's compression, not
  # upscaling).
  def frame_timestamps(walkthrough, crisp_source: true)
    entries = walkthrough.analysis_issues.filter_map do |issue|
      seconds = Gemini::FrameExtractor.parse_timestamp(issue["timestamp"])
      next unless seconds

      flagged = flagged_issue?(issue)
      hi_res = flagged && crisp_source
      {
        seconds: seconds,
        label: issue["title"].to_s,
        flagged: flagged,
        scale_width: hi_res ? Gemini::FrameExtractor::HIGH_SCALE_WIDTH : Gemini::FrameExtractor::SCALE_WIDTH,
        jpeg_quality: flagged ? Gemini::FrameExtractor::HIGH_JPEG_QUALITY : Gemini::FrameExtractor::JPEG_QUALITY
      }
    end

    prioritize_flagged(entries)
  end

  # An issue whose important on-screen text the video model couldn't read: the
  # explicit unreadable_text handoff, or the broader needs_closer_look signal.
  def flagged_issue?(issue)
    issue["needs_closer_look"] || issue["unreadable_text"].to_s.strip.present?
  end

  # Keep every flagged issue within the frame cap (they're the ones the agent
  # OCRs), fill the remaining slots with the earliest unflagged issues, then
  # restore original issue order so screenshots line up with the issue list.
  def prioritize_flagged(entries)
    cap = Gemini::FrameExtractor::MAX_FRAMES
    return entries if entries.size <= cap

    indexed = entries.each_with_index.to_a
    flagged, plain = indexed.partition { |entry, _index| entry[:flagged] }
    (flagged + plain).first(cap).sort_by { |_entry, index| index }.map(&:first)
  end

  # Re-delivery path: the analysis persisted but the chat turn didn't. Pull
  # frames from whatever video is still stored (the compact ~720p mp4 by now, or
  # nothing if pruned). crisp_source: false so flagged frames capture at the
  # compact width instead of upscaling the stored 720p. Text-only if unavailable.
  def reextract_frame_attachments(walkthrough)
    return [] unless walkthrough.file.attached?

    with_local_video(walkthrough) { |path| build_frame_attachments(walkthrough, path, crisp_source: false) }
  rescue StandardError
    []
  end

  def transition!(walkthrough, state)
    walkthrough.update!(state: state)
    broadcast(walkthrough)
  end

  def fail_walkthrough!(walkthrough, message)
    return unless walkthrough

    walkthrough.update!(state: "failed", error_message: message)
    broadcast(walkthrough)
  end

  def broadcast(walkthrough)
    AppEvents.broadcast(
      user: walkthrough.user,
      type: "video_walkthrough.#{walkthrough.state}",
      resource: "video_walkthrough",
      id: walkthrough.id,
      payload: {
        chat_session_id: walkthrough.chat_session_id,
        state: walkthrough.state,
        error_message: walkthrough.error_message
      }
    )
  end
end
