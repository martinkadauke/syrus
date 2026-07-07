# The video→Epic pipeline's middle: take an uploaded ChatVideoWalkthrough,
# run it through Gemini (Files API upload → poll ACTIVE → one structured
# generateContent), persist the analysis, and inject it into the chat as a
# queued user-role turn so the chat agent — the thing that already knows how
# to ask follow-ups and propose Epics — takes over. Runs on `default`, not
# the low-concurrency `chat` queue: a multi-minute Gemini poll must never
# starve actual chat turns.
class VideoWalkthroughAnalysisJob < ApplicationJob
  queue_as :default

  # Test seam, mirroring RunJob.agent_runner: specs swap in a fake client
  # factory instead of stubbing Net::HTTP.
  class << self
    attr_writer :client_factory

    def client_factory
      @client_factory ||= ->(api_key:) { Gemini::Client.new(api_key: api_key) }
    end
  end

  def perform(walkthrough_id, user_note: nil)
    walkthrough = ChatVideoWalkthrough.find_by(id: walkthrough_id)
    return unless walkthrough&.uploaded?

    user = walkthrough.user
    unless user.gemini_configured?
      fail_walkthrough!(walkthrough, "Gemini is not configured — add an API key under Credentials.")
      return
    end

    transition!(walkthrough, "analyzing")
    client = self.class.client_factory.call(api_key: user.gemini_api_key)

    analysis = analyze(client, walkthrough)
    walkthrough.update!(state: "analyzed", analysis: analysis, analyzed_at: Time.current, error_message: nil)
    broadcast(walkthrough)

    inject_chat_turn(walkthrough, user_note)
  rescue Gemini::Client::AuthError => error
    fail_walkthrough!(walkthrough, "Gemini rejected the API key: #{error.message} Check it under Credentials.")
  rescue Gemini::Client::RateLimited
    fail_walkthrough!(
      walkthrough,
      "Gemini's quota is busy right now (free-tier limits are per-minute). Retry the analysis in a minute or two, or enable billing on your AI Studio project."
    )
  rescue Gemini::Client::Error => error
    fail_walkthrough!(walkthrough, error.message)
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

  def inject_chat_turn(walkthrough, user_note)
    chat = walkthrough.chat_session
    text = Prompts::VideoWalkthroughContext.new(walkthrough: walkthrough, user_note: user_note).to_s
    chat.queued_messages.create!(content: { "text" => text, "video_walkthrough_id" => walkthrough.id })
    # Delivers immediately when the agent is idle; otherwise ChatTurnJob's
    # turn-end promotion picks it up — either way, no turn collision.
    ChatQueuedMessagePromoter.deliver_one_if_idle!(chat)
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
