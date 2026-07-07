# The video→Epic pipeline's middle: take an uploaded ChatVideoWalkthrough,
# run it through Gemini (Files API upload → poll ACTIVE → one structured
# generateContent), persist the analysis, and inject it into the chat as a
# queued user-role turn so the chat agent — the thing that already knows how
# to ask follow-ups and propose Epics — takes over.
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
      walkthrough.update!(analysis: analyze(client, walkthrough))
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

  def analyze(client, walkthrough)
    file = upload_to_gemini(client, walkthrough)
    active = client.wait_until_active(file.fetch("name"))
    walkthrough.update!(gemini_file_uri: active["uri"], gemini_file_active_at: Time.current)

    client.generate_content(
      file_uri: active.fetch("uri"),
      mime_type: walkthrough.content_type,
      prompt: Prompts::VideoWalkthroughAnalysis.new.to_s,
      response_schema: Prompts::VideoWalkthroughAnalysis::RESPONSE_SCHEMA,
      duration_seconds: walkthrough.duration_seconds
    )
  end

  def upload_to_gemini(client, walkthrough)
    # Stream the blob straight from Active Storage to Gemini without loading
    # 100-500MB into memory: open a tempfile-backed download and hand the IO
    # to the resumable upload.
    walkthrough.file.open do |tempfile|
      client.upload_file(
        io: tempfile,
        byte_size: walkthrough.byte_size,
        content_type: walkthrough.content_type,
        display_name: walkthrough.display_title
      )
    end
  end

  # Inject the analysis as a queued chat turn. Returns true once the message
  # is queued (whether or not the promoter delivers it immediately — a busy
  # agent legitimately defers it). Returns false and marks the row failed if
  # queueing itself raises, so the analysis isn't reported as success when
  # its turn never reached the chat; retry re-delivers without re-analyzing.
  def deliver_chat_turn(walkthrough)
    chat = walkthrough.chat_session
    text = Prompts::VideoWalkthroughContext.new(walkthrough: walkthrough, user_note: walkthrough.note).to_s
    chat.queued_messages.create!(content: { "text" => text, "video_walkthrough_id" => walkthrough.id })
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
