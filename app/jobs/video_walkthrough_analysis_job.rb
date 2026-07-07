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
      @screenshot_attachments = build_frame_attachments(walkthrough, video_path)
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
    walkthrough.update!(gemini_file_uri: active["uri"], gemini_file_active_at: Time.current)

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
      prompt: Prompts::VideoWalkthroughAnalysis.new.to_s,
      response_schema: Prompts::VideoWalkthroughAnalysis::RESPONSE_SCHEMA,
      media_resolution: media_resolution
    )
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
      File.open(mp4, "rb") do |io|
        walkthrough.file.attach(io: io, filename: "#{base}.mp4", content_type: "video/mp4")
      end
      walkthrough.update!(content_type: "video/mp4", byte_size: File.size(mp4))
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
    # re-extract from whatever video is still stored.
    attachments = @screenshot_attachments || reextract_frame_attachments(walkthrough)
    text = Prompts::VideoWalkthroughContext.new(
      walkthrough: walkthrough, user_note: walkthrough.note, illustrated: attachments.any?
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

  # Grab one screen frame per flagged issue (at Gemini's timestamp) from the
  # given local video, so the chat agent SEES each problem and the UI shows
  # it. Best-effort: any failure (no ffmpeg, bad timestamp) yields no
  # attachments and the turn ships text-only. Frames become base64 image
  # attachments, the same shape chat already uses for pasted screenshots.
  def build_frame_attachments(walkthrough, video_path)
    timestamps = walkthrough.analysis_issues.filter_map do |issue|
      seconds = Gemini::FrameExtractor.parse_timestamp(issue["timestamp"])
      next unless seconds

      { seconds: seconds, label: issue["title"].to_s }
    end
    return [] if timestamps.empty?

    Gemini::FrameExtractor.extract(video_path: video_path, timestamps: timestamps).map do |frame|
      clock = format("%d:%02d", frame.seconds / 60, frame.seconds % 60)
      { "name" => "walkthrough #{clock} — #{frame.label}".strip, "mime_type" => "image/jpeg",
        "data" => Base64.strict_encode64(frame.jpeg) }
    end
  rescue StandardError => error
    Rails.logger.warn("[VideoWalkthroughAnalysisJob] frame extraction failed: #{error.class}: #{error.message}")
    []
  end

  # Re-delivery path: the analysis persisted but the chat turn didn't. Pull
  # frames from whatever video is still stored (the compact mp4 by now, or
  # nothing if pruned). Text-only if unavailable.
  def reextract_frame_attachments(walkthrough)
    return [] unless walkthrough.file.attached?

    with_local_video(walkthrough) { |path| build_frame_attachments(walkthrough, path) }
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
