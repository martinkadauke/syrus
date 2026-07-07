require "rails_helper"

# Fake Gemini client mirroring exactly the three calls the job makes
# (upload_file → wait_until_active → generate_content). Swapped in through
# the VideoWalkthroughAnalysisJob.client_factory test seam so no Net::HTTP
# stubbing is needed.
class FakeGeminiWalkthroughClient
  attr_reader :upload_calls, :generate_calls

  def initialize(analysis: {}, raise_on_upload: nil)
    @analysis = analysis
    @raise_on_upload = raise_on_upload
    @upload_calls = []
    @generate_calls = []
  end

  def upload_file(io:, byte_size:, content_type:, display_name:)
    raise @raise_on_upload if @raise_on_upload

    @upload_calls << { byte_size: byte_size, content_type: content_type, display_name: display_name, read: io.read }
    { "name" => "files/fake-123", "uri" => "https://generativelanguage.googleapis.com/v1beta/files/fake-123", "state" => "PROCESSING" }
  end

  def wait_until_active(name)
    { "name" => name, "uri" => "https://generativelanguage.googleapis.com/v1beta/files/fake-123", "state" => "ACTIVE" }
  end

  def generate_content(file_uri:, mime_type:, prompt:, response_schema:, duration_seconds: nil)
    @generate_calls << {
      file_uri: file_uri, mime_type: mime_type, prompt: prompt,
      response_schema: response_schema, duration_seconds: duration_seconds
    }
    @analysis
  end
end

RSpec.describe VideoWalkthroughAnalysisJob do
  let(:user) { Factories.user(gemini_api_key: "gk-test") }
  let(:chat) { ChatSession.create!(user: user) }

  let(:analysis) do
    {
      "summary" => "The checkout flow mostly works, but saving settings fails silently.",
      "issues" => [
        {
          "title" => "Save button does nothing",
          "severity" => "major",
          "area" => "settings",
          "timestamp" => "01:12",
          "detail" => "Clicking Save shows no feedback and persists nothing."
        }
      ],
      "open_questions" => [ "Should drafts autosave?" ]
    }
  end

  let(:fake_client) { FakeGeminiWalkthroughClient.new(analysis: analysis) }
  let(:factory_api_keys) { [] }

  around do |example|
    original = described_class.client_factory
    begin
      example.run
    ensure
      described_class.client_factory = original
    end
  end

  before do
    allow(AppEvents).to receive(:broadcast)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    described_class.client_factory = lambda do |api_key:|
      factory_api_keys << api_key
      fake_client
    end
  end

  def create_walkthrough(**attrs)
    ChatVideoWalkthrough.new({
      chat_session: chat,
      user: user,
      content_type: "video/webm",
      byte_size: 10,
      duration_seconds: 95,
      title: "Checkout run"
    }.merge(attrs)).tap do |walkthrough|
      walkthrough.file.attach(io: StringIO.new("webm-bytes"), filename: "walkthrough.webm", content_type: "video/webm")
      walkthrough.save!
    end
  end

  describe "happy path" do
    it "analyzes the video, persists the analysis, and injects the queued chat turn" do
      walkthrough = create_walkthrough

      described_class.perform_now(walkthrough.id, user_note: "Watch the save button")

      walkthrough.reload
      expect(walkthrough).to be_analyzed
      expect(walkthrough.analysis).to eq(analysis)
      expect(walkthrough.gemini_file_uri).to eq("https://generativelanguage.googleapis.com/v1beta/files/fake-123")
      expect(walkthrough.gemini_file_active_at).to be_present
      expect(walkthrough.analyzed_at).to be_present
      expect(walkthrough.error_message).to be_nil

      expect(factory_api_keys).to eq([ "gk-test" ])
      expect(fake_client.upload_calls.size).to eq(1)
      expect(fake_client.upload_calls.first).to include(
        byte_size: 10, content_type: "video/webm", display_name: "Checkout run", read: "webm-bytes"
      )
      expect(fake_client.generate_calls.size).to eq(1)
      expect(fake_client.generate_calls.first).to include(
        file_uri: "https://generativelanguage.googleapis.com/v1beta/files/fake-123",
        mime_type: "video/webm",
        duration_seconds: 95
      )

      queued = chat.chat_queued_messages.order(:id).last
      expect(queued).to be_present
      expect(queued.text).to include("Save button does nothing")
      expect(queued.text).to include("propose an Epic")
      expect(queued.text).to include("The user's note with the video: Watch the save button")
      expect(queued.content["video_walkthrough_id"]).to eq(walkthrough.id)
    end

    it "promotes the queued message into a ChatMessage and enqueues a ChatTurnJob when the chat is idle" do
      # A chat with no messages, no in-flight turn, no running agent process,
      # and no stop request is idle per ChatQueuedMessagePromoter, so the
      # injected turn is delivered immediately.
      walkthrough = create_walkthrough

      described_class.perform_now(walkthrough.id)

      queued = chat.chat_queued_messages.order(:id).last
      expect(queued.delivered_at).to be_present

      user_messages = chat.messages.where(role: "user")
      expect(user_messages.count).to eq(1)
      expect(user_messages.last.content["text"]).to eq(queued.text)

      turn_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == ChatTurnJob }
      expect(turn_jobs.size).to eq(1)
      expect(turn_jobs.first[:args]).to eq([ chat.id, user_messages.last.id ])
    end

    it "broadcasts analyzing and analyzed state changes" do
      walkthrough = create_walkthrough

      described_class.perform_now(walkthrough.id)

      expect(AppEvents).to have_received(:broadcast).with(
        hash_including(user: user, type: "video_walkthrough.analyzing", resource: "video_walkthrough", id: walkthrough.id)
      )
      expect(AppEvents).to have_received(:broadcast).with(
        hash_including(user: user, type: "video_walkthrough.analyzed", resource: "video_walkthrough", id: walkthrough.id)
      )
    end
  end

  describe "user without a Gemini key" do
    it "fails with a not-configured message and never builds a client" do
      keyless = Factories.user
      keyless_chat = ChatSession.create!(user: keyless)
      walkthrough = create_walkthrough(chat_session: keyless_chat, user: keyless)

      described_class.perform_now(walkthrough.id)

      walkthrough.reload
      expect(walkthrough).to be_failed
      expect(walkthrough.error_message).to include("not configured")
      expect(factory_api_keys).to be_empty
      expect(fake_client.upload_calls).to be_empty
      expect(AppEvents).to have_received(:broadcast).with(
        hash_including(type: "video_walkthrough.failed", id: walkthrough.id)
      )
      expect(keyless_chat.chat_queued_messages.count).to eq(0)
    end
  end

  describe "Gemini errors" do
    let(:fake_client) { FakeGeminiWalkthroughClient.new(raise_on_upload: error) }

    context "auth error" do
      let(:error) { Gemini::Client::AuthError.new("API key not valid.") }

      it "fails and points at the key" do
        walkthrough = create_walkthrough

        described_class.perform_now(walkthrough.id)

        walkthrough.reload
        expect(walkthrough).to be_failed
        expect(walkthrough.error_message).to include("Gemini rejected the API key")
        expect(walkthrough.error_message).to include("API key not valid.")
        expect(walkthrough.error_message).to include("Credentials")
        expect(AppEvents).to have_received(:broadcast).with(
          hash_including(type: "video_walkthrough.failed", id: walkthrough.id)
        )
      end
    end

    context "rate limited" do
      let(:error) { Gemini::Client::RateLimited.new("429") }

      it "fails with the quota message" do
        walkthrough = create_walkthrough

        described_class.perform_now(walkthrough.id)

        walkthrough.reload
        expect(walkthrough).to be_failed
        expect(walkthrough.error_message).to include("quota")
      end
    end

    context "generic client error" do
      let(:error) { Gemini::Client::Error.new("Gemini returned an empty analysis") }

      it "fails with the error text" do
        walkthrough = create_walkthrough

        described_class.perform_now(walkthrough.id)

        walkthrough.reload
        expect(walkthrough).to be_failed
        expect(walkthrough.error_message).to eq("Gemini returned an empty analysis")
      end
    end
  end

  describe "no-op guards" do
    it "returns without side effects when the walkthrough is already analyzed" do
      walkthrough = create_walkthrough(state: "analyzed")

      described_class.perform_now(walkthrough.id)

      expect(walkthrough.reload.state).to eq("analyzed")
      expect(factory_api_keys).to be_empty
      expect(AppEvents).not_to have_received(:broadcast)
      expect(chat.chat_queued_messages.count).to eq(0)
    end

    it "returns without raising for a missing walkthrough id" do
      missing_id = ChatVideoWalkthrough.maximum(:id).to_i + 1

      expect { described_class.perform_now(missing_id) }.not_to raise_error
      expect(factory_api_keys).to be_empty
      expect(AppEvents).not_to have_received(:broadcast)
    end
  end
end
