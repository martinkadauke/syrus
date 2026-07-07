require "rails_helper"

RSpec.describe Gemini::FrameExtractor do
  # Status double: responds to success? like Process::Status does, so the
  # extractor's `status.respond_to?(:success?) ? ... : ...` branch takes the
  # success? path.
  Status = Struct.new(:success) do
    def success?
      success
    end
  end

  def ok_status
    Status.new(true)
  end

  def fail_status
    Status.new(false)
  end

  # Restore the class-level runner seam after every example that swaps it.
  around do |example|
    original = described_class.runner
    begin
      example.run
    ensure
      described_class.runner = original
    end
  end

  describe ".parse_timestamp" do
    {
      "00:06" => 6,
      "1:16" => 76,
      "01:12" => 72,
      "1:02:03" => 3723,
      "90" => 90,
      "0" => 0,
      "" => nil,
      "   " => nil,
      "garbage" => nil,
      "-5" => nil,
      "1:2:3:4" => nil,
      nil => nil
    }.each do |input, expected|
      it "parses #{input.inspect} → #{expected.inspect}" do
        expect(described_class.parse_timestamp(input)).to eq(expected)
      end
    end
  end

  describe ".available?" do
    it "is true when the runner reports ffmpeg -version success" do
      described_class.runner = ->(cmd) { expect(cmd).to eq(%w[ffmpeg -version]); [ "ffmpeg version 6.0", ok_status ] }

      expect(described_class.available?).to be true
    end

    it "is false when the runner reports a non-success status" do
      described_class.runner = ->(_cmd) { [ "not found", fail_status ] }

      expect(described_class.available?).to be false
    end

    it "is false when the runner raises Errno::ENOENT (ffmpeg absent)" do
      described_class.runner = ->(_cmd) { raise Errno::ENOENT, "No such file - ffmpeg" }

      expect(described_class.available?).to be false
    end
  end

  describe ".extract" do
    # A runner that stands in for the real ffmpeg call: the out path is the
    # last element of the cmd array, so we "produce" a frame by writing JPEG
    # bytes there and reporting success. `-version` (availability probe) is
    # answered separately so available? returns true.
    def writing_runner(jpeg_bytes: "jpeg-bytes")
      lambda do |cmd|
        if cmd == %w[ffmpeg -version]
          [ "ffmpeg version 6.0", ok_status ]
        else
          File.binwrite(cmd.last, jpeg_bytes)
          [ "", ok_status ]
        end
      end
    end

    it "returns [] when ffmpeg is unavailable" do
      described_class.runner = ->(_cmd) { [ "", fail_status ] } # -version fails → not available

      frames = described_class.extract(
        video_path: "/tmp/video.webm",
        timestamps: [ { seconds: 5, label: "Issue" } ]
      )

      expect(frames).to eq([])
    end

    it "returns [] for blank timestamps" do
      described_class.runner = writing_runner

      expect(described_class.extract(video_path: "/tmp/video.webm", timestamps: [])).to eq([])
      expect(described_class.extract(video_path: "/tmp/video.webm", timestamps: nil)).to eq([])
    end

    it "extracts a frame per timestamp with the right seconds and label" do
      described_class.runner = writing_runner(jpeg_bytes: "the-jpeg")

      frames = described_class.extract(
        video_path: "/tmp/video.webm",
        timestamps: [
          { seconds: 12, label: "Save button" },
          { seconds: 90, label: "NaN total" }
        ]
      )

      expect(frames.size).to eq(2)
      expect(frames.map(&:seconds)).to eq([ 12, 90 ])
      expect(frames.map(&:label)).to eq([ "Save button", "NaN total" ])
      expect(frames.map(&:jpeg)).to all(eq("the-jpeg"))
      expect(frames).to all(be_a(Gemini::FrameExtractor::Frame))
    end

    it "skips negative and nil timestamps but keeps the valid ones" do
      described_class.runner = writing_runner

      frames = described_class.extract(
        video_path: "/tmp/video.webm",
        timestamps: [
          { seconds: -5, label: "before start" },
          { seconds: nil, label: "unparseable" },
          { seconds: 20, label: "real issue" }
        ]
      )

      expect(frames.map(&:seconds)).to eq([ 20 ])
      expect(frames.map(&:label)).to eq([ "real issue" ])
    end

    it "skips frames the runner fails to produce (no jpeg written)" do
      described_class.runner = lambda do |cmd|
        if cmd == %w[ffmpeg -version]
          [ "", ok_status ]
        else
          # Report success but write nothing → File.exist?(out) is false → skip.
          [ "", ok_status ]
        end
      end

      frames = described_class.extract(
        video_path: "/tmp/video.webm",
        timestamps: [ { seconds: 10, label: "vanishes" } ]
      )

      expect(frames).to eq([])
    end

    it "caps output at MAX_FRAMES even when more timestamps are supplied" do
      described_class.runner = writing_runner
      timestamps = (1..(described_class::MAX_FRAMES + 5)).map { |n| { seconds: n, label: "issue #{n}" } }

      frames = described_class.extract(video_path: "/tmp/video.webm", timestamps: timestamps)

      expect(frames.size).to eq(described_class::MAX_FRAMES)
      # First MAX_FRAMES timestamps, in order.
      expect(frames.map(&:seconds)).to eq((1..described_class::MAX_FRAMES).to_a)
    end
  end
end
