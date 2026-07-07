require "rails_helper"

# Fake Gemini client mirroring exactly the three calls the job makes
# (upload_file → wait_until_active → generate_content). Swapped in through
# the VideoWalkthroughAnalysisJob.client_factory test seam so no Net::HTTP
# stubbing is needed.
class FakeGeminiWalkthroughClient
  attr_reader :upload_calls, :generate_calls, :resolve_calls

  # `raise_on_generate` raises the given error(s) on generate_content. Pass a
  # single error to raise on every call, or an array to raise per-call in order
  # (nil entries succeed) — this models the analysis job's full-res → low-res
  # retry ladder, where the first call is RateLimited and the second succeeds.
  def initialize(analysis: {}, raise_on_upload: nil, raise_on_generate: nil)
    @analysis = analysis
    @raise_on_upload = raise_on_upload
    @raise_on_generate = raise_on_generate
    @upload_calls = []
    @generate_calls = []
    @resolve_calls = 0
  end

  # The job resolves the model against the key's project before analyzing
  # (Gemini::Client#resolve_video_model!); the fake records the call and
  # is a no-op otherwise.
  def resolve_video_model!
    @resolve_calls += 1
    "gemini-3.5-flash"
  end

  def upload_file(io:, byte_size:, content_type:, display_name:)
    raise @raise_on_upload if @raise_on_upload

    @upload_calls << { byte_size: byte_size, content_type: content_type, display_name: display_name, read: io.read }
    { "name" => "files/fake-123", "uri" => "https://generativelanguage.googleapis.com/v1beta/files/fake-123", "state" => "PROCESSING" }
  end

  def wait_until_active(name)
    { "name" => name, "uri" => "https://generativelanguage.googleapis.com/v1beta/files/fake-123", "state" => "ACTIVE" }
  end

  def generate_content(file_uri:, mime_type:, prompt:, response_schema:, media_resolution: :default)
    @generate_calls << {
      file_uri: file_uri, mime_type: mime_type, prompt: prompt,
      response_schema: response_schema, media_resolution: media_resolution
    }

    if @raise_on_generate.is_a?(Array)
      error = @raise_on_generate[@generate_calls.size - 1]
      raise error if error
    elsif @raise_on_generate
      raise @raise_on_generate
    end

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
      walkthrough = create_walkthrough(note: "Watch the save button")

      described_class.perform_now(walkthrough.id)

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
        media_resolution: :default
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

  # Regression: a transport failure from Gemini used to escape the rescue
  # chain (only Net::* / specific Gemini errors were caught), leaving the
  # walkthrough stranded in "analyzing" with a forever-spinning chip. The
  # client now wraps transport failures as Gemini::Client::ConnectionError and
  # the job rescues it into a terminal "failed" state.
  describe "transient network failure" do
    let(:fake_client) do
      FakeGeminiWalkthroughClient.new(raise_on_upload: Gemini::Client::ConnectionError.new("could not reach Gemini"))
    end

    it "marks the walkthrough failed (never stuck analyzing) and broadcasts the failure" do
      walkthrough = create_walkthrough

      described_class.perform_now(walkthrough.id)

      walkthrough.reload
      expect(walkthrough).to be_failed
      expect(walkthrough.state).not_to eq("analyzing")
      expect(walkthrough.error_message).to include("Could not reach Gemini")
      expect(AppEvents).to have_received(:broadcast).with(
        hash_including(type: "video_walkthrough.failed", id: walkthrough.id)
      )
    end
  end

  # Regression: any unexpected exception class (not just the Gemini hierarchy)
  # must be caught by the StandardError catch-all so nothing can strand the
  # walkthrough in "analyzing". A bare RuntimeError used to propagate.
  describe "unexpected error via the StandardError catch-all" do
    let(:fake_client) { FakeGeminiWalkthroughClient.new(raise_on_upload: RuntimeError.new("boom")) }

    it "marks the walkthrough failed instead of propagating" do
      walkthrough = create_walkthrough

      expect { described_class.perform_now(walkthrough.id) }.not_to raise_error

      walkthrough.reload
      expect(walkthrough).to be_failed
      expect(walkthrough.state).not_to eq("analyzing")
      expect(walkthrough.error_message).to include("unexpected error")
      expect(walkthrough.error_message).to include("RuntimeError")
    end
  end

  # Regression: a chat-delivery failure must not masquerade as analysis
  # success. Delivery runs BEFORE the "analyzed" broadcast/state: if it raises,
  # deliver_chat_turn marks the row failed with a "succeeded but posting"
  # message and the job returns without ever broadcasting "analyzed". Ordering
  # matters — an "analyzed" broadcast first would clear the frontend chip and
  # make the subsequent "failed" event a no-op, hiding the failure.
  describe "chat delivery failure" do
    it "ends failed with the posting message and never broadcasts analyzed, though the analysis persisted" do
      walkthrough = create_walkthrough
      allow(ChatQueuedMessagePromoter).to receive(:deliver_one_if_idle!).and_raise(RuntimeError.new("promotion blew up"))

      described_class.perform_now(walkthrough.id)

      walkthrough.reload
      expect(walkthrough).to be_failed
      expect(walkthrough.error_message).to include("succeeded but posting")
      # Analysis is preserved so a retry skips Gemini and just re-delivers.
      expect(walkthrough.analysis).to eq(analysis)
      # The frontend only ever sees analyzing → failed, never analyzed-then-failed.
      expect(AppEvents).to have_received(:broadcast).with(
        hash_including(type: "video_walkthrough.analyzing", id: walkthrough.id)
      )
      expect(AppEvents).to have_received(:broadcast).with(
        hash_including(type: "video_walkthrough.failed", id: walkthrough.id)
      )
      expect(AppEvents).not_to have_received(:broadcast).with(
        hash_including(type: "video_walkthrough.analyzed")
      )
    end
  end

  # Regression / re-delivery path: a retried walkthrough whose analysis already
  # succeeded (the earlier failure was in chat delivery) must NOT re-hit Gemini
  # — the 48h Files-API retention makes re-analysis wasteful — but must still
  # inject the chat turn.
  describe "re-delivery path (analysis already present)" do
    it "skips Gemini entirely but still injects the queued chat turn" do
      walkthrough = create_walkthrough(analysis: analysis)

      described_class.perform_now(walkthrough.id)

      walkthrough.reload
      expect(walkthrough).to be_analyzed
      expect(fake_client.upload_calls).to be_empty
      expect(fake_client.generate_calls).to be_empty
      expect(fake_client.resolve_calls).to eq(0)

      queued = chat.chat_queued_messages.order(:id).last
      expect(queued).to be_present
      expect(queued.text).to include("Save button does nothing")
      expect(queued.content["video_walkthrough_id"]).to eq(walkthrough.id)
    end
  end

  # Graceful degradation: a long video at full resolution can blow the
  # free-tier per-minute token window. The job retries ONCE at low resolution,
  # but only for videos at/beyond the fallback threshold — a short video that
  # gets rate-limited is a genuine transient blip and re-fails outright.
  describe "rate-limit graceful degradation" do
    context "short video (duration < threshold)" do
      let(:fake_client) do
        FakeGeminiWalkthroughClient.new(
          analysis: analysis,
          raise_on_generate: Gemini::Client::RateLimited.new("429")
        )
      end

      it "fails with the quota message and never retries at low resolution" do
        short = (Gemini::Client::LOW_RESOLUTION_FALLBACK_SECONDS - 1)
        walkthrough = create_walkthrough(duration_seconds: short)

        described_class.perform_now(walkthrough.id)

        walkthrough.reload
        expect(walkthrough).to be_failed
        expect(walkthrough.error_message).to include("quota")
        # Exactly one generate attempt — no low-res retry for short videos.
        expect(fake_client.generate_calls.size).to eq(1)
        expect(fake_client.generate_calls.first[:media_resolution]).to eq(:default)
      end
    end

    context "long video (duration >= threshold)" do
      let(:fake_client) do
        FakeGeminiWalkthroughClient.new(
          analysis: analysis,
          # First (full-res) call is rate-limited; second (low-res) succeeds.
          raise_on_generate: [ Gemini::Client::RateLimited.new("429"), nil ]
        )
      end

      it "retries at low resolution and succeeds" do
        long = Gemini::Client::LOW_RESOLUTION_FALLBACK_SECONDS
        walkthrough = create_walkthrough(duration_seconds: long)

        described_class.perform_now(walkthrough.id)

        walkthrough.reload
        expect(walkthrough).to be_analyzed
        expect(walkthrough.analysis).to eq(analysis)
        # Two attempts: the first at full res, the retry at low res.
        expect(fake_client.generate_calls.size).to eq(2)
        expect(fake_client.generate_calls[0][:media_resolution]).to eq(:default)
        expect(fake_client.generate_calls[1][:media_resolution]).to eq(:low)
      end
    end
  end

  # Best-effort frame extraction: the job grabs one screen frame per flagged
  # issue (at Gemini's timestamp) via Gemini::FrameExtractor and attaches them
  # to the injected chat turn. Any extraction failure degrades to text-only.
  describe "issue frame extraction" do
    def frame(seconds:, label:, jpeg:)
      Gemini::FrameExtractor::Frame.new(seconds: seconds, label: label, jpeg: jpeg)
    end

    it "attaches extracted frames and notes the screenshots in the turn text" do
      allow(Gemini::FrameExtractor).to receive(:extract).and_return([
        frame(seconds: 72, label: "Save button does nothing", jpeg: "jpeg-A"),
        frame(seconds: 6, label: "Second thing", jpeg: "jpeg-B")
      ])
      walkthrough = create_walkthrough

      described_class.perform_now(walkthrough.id)

      queued = chat.chat_queued_messages.order(:id).last
      attachments = queued.content["attachments"]
      expect(attachments.size).to eq(2)
      expect(attachments).to all(include("mime_type" => "image/jpeg"))
      expect(attachments.map { |a| a["data"] }).to eq(
        [ Base64.strict_encode64("jpeg-A"), Base64.strict_encode64("jpeg-B") ]
      )
      # illustrated: true → the screenshots note appears in the text.
      expect(queued.text).to include("attached a screenshot for each issue")
    end

    it "ships text-only with no attachments note when extraction returns []" do
      # e.g. no ffmpeg in dev — FrameExtractor.extract returns [].
      allow(Gemini::FrameExtractor).to receive(:extract).and_return([])
      walkthrough = create_walkthrough

      described_class.perform_now(walkthrough.id)

      queued = chat.chat_queued_messages.order(:id).last
      expect(queued.content).not_to have_key("attachments")
      expect(queued.text).not_to include("attached a screenshot for each issue")
    end

    it "still delivers text-only (analyzed, not failed) when extraction raises" do
      allow(Gemini::FrameExtractor).to receive(:extract).and_raise(RuntimeError.new("ffmpeg exploded"))
      walkthrough = create_walkthrough

      expect { described_class.perform_now(walkthrough.id) }.not_to raise_error

      walkthrough.reload
      expect(walkthrough).to be_analyzed
      expect(walkthrough.error_message).to be_nil

      queued = chat.chat_queued_messages.order(:id).last
      expect(queued).to be_present
      expect(queued.content).not_to have_key("attachments")
      expect(queued.text).to include("Save button does nothing")
    end
  end

  # Storage transcode: after analysis + screenshots, compact_for_storage
  # transcodes the crisp source to a compact 720p mp4 that REPLACES the stored
  # blob so the durable artifact is small. Best-effort — no ffmpeg keeps the
  # original webm; a working transcode swaps in the mp4.
  describe "storage transcode (compact_for_storage)" do
    around do |example|
      original = Gemini::VideoTranscoder.runner
      begin
        example.run
      ensure
        Gemini::VideoTranscoder.runner = original
      end
    end

    it "keeps the original webm blob when ffmpeg is unavailable" do
      # available? is false in-container (no ffmpeg) — the default. Assert the
      # stored file is untouched (still webm) and no transcode is attempted.
      allow(Gemini::VideoTranscoder).to receive(:available?).and_return(false)
      expect(Gemini::VideoTranscoder).not_to receive(:to_compact_mp4)
      walkthrough = create_walkthrough

      described_class.perform_now(walkthrough.id)

      walkthrough.reload
      expect(walkthrough).to be_analyzed
      expect(walkthrough.content_type).to eq("video/webm")
      expect(walkthrough.file.content_type).to eq("video/webm")
      expect(walkthrough.file.filename.to_s).to eq("walkthrough.webm")
    end

    it "replaces the stored blob with the compact mp4 and updates content_type + byte_size" do
      # Stub the transcoder available and have to_compact_mp4 actually produce a
      # (fake) mp4 at output_path so the job's attach + update! path runs.
      mp4_bytes = "fake-mp4-bytes-that-are-a-bit-longer-than-the-webm"
      allow(Gemini::VideoTranscoder).to receive(:available?).and_return(true)
      allow(Gemini::VideoTranscoder).to receive(:to_compact_mp4) do |input_path:, output_path:|
        expect(File.exist?(input_path)).to be true
        File.binwrite(output_path, mp4_bytes)
        true
      end
      walkthrough = create_walkthrough

      described_class.perform_now(walkthrough.id)

      walkthrough.reload
      expect(walkthrough).to be_analyzed
      # The stored blob was swapped for the compact mp4.
      expect(walkthrough.content_type).to eq("video/mp4")
      expect(walkthrough.byte_size).to eq(mp4_bytes.bytesize)
      expect(walkthrough.file.content_type).to eq("video/mp4")
      expect(walkthrough.file.filename.to_s).to eq("walkthrough.mp4")
      expect(walkthrough.file.download).to eq(mp4_bytes)
    end

    it "keeps the original blob when the transcode fails (returns false)" do
      allow(Gemini::VideoTranscoder).to receive(:available?).and_return(true)
      allow(Gemini::VideoTranscoder).to receive(:to_compact_mp4).and_return(false)
      walkthrough = create_walkthrough

      described_class.perform_now(walkthrough.id)

      walkthrough.reload
      expect(walkthrough).to be_analyzed
      expect(walkthrough.content_type).to eq("video/webm")
      expect(walkthrough.file.content_type).to eq("video/webm")
    end

    it "still ends analyzed (keeping the original) when the transcode raises" do
      allow(Gemini::VideoTranscoder).to receive(:available?).and_return(true)
      allow(Gemini::VideoTranscoder).to receive(:to_compact_mp4).and_raise(RuntimeError.new("ffmpeg blew up"))
      walkthrough = create_walkthrough

      expect { described_class.perform_now(walkthrough.id) }.not_to raise_error

      walkthrough.reload
      expect(walkthrough).to be_analyzed
      expect(walkthrough.error_message).to be_nil
      expect(walkthrough.content_type).to eq("video/webm")
    end
  end

  describe "queue" do
    it "runs on the dedicated videos queue" do
      expect(described_class.new.queue_name).to eq("videos")
    end
  end

  # Regression: the note is read from the persisted column, not a job kwarg.
  # Prompts::VideoWalkthroughContext renders it as the user's note, so the
  # injected queued message must include it.
  describe "note from the persisted column" do
    it "renders the persisted note into the injected chat turn" do
      walkthrough = create_walkthrough(note: "Focus on the flaky Save button")

      described_class.perform_now(walkthrough.id)

      queued = chat.chat_queued_messages.order(:id).last
      expect(queued.text).to include("The user's note with the video: Focus on the flaky Save button")
    end
  end
end
