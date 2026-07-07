require "open3"
require "shellwords"

module Gemini
  # Extracts still frames from a walkthrough video at the timestamps Gemini
  # flagged, so the analysis chat turn can SHOW each issue rather than only
  # describe it — the chat agent gets visual grounding (better Epics) and the
  # UI renders the screenshots inline.
  #
  # Runs ffmpeg (added to the runtime image). Every failure mode — ffmpeg
  # missing (dev), a bad timestamp, a corrupt seek — degrades to "no frame for
  # this issue" and never blocks the analysis turn. Frames are downscaled JPEGs
  # so they stay small as base64 message attachments.
  class FrameExtractor
    Frame = Struct.new(:seconds, :label, :jpeg, keyword_init: true)

    # Bound the message size + ffmpeg work: at most this many frames per video.
    MAX_FRAMES = 8
    # ~720p wide is plenty to read a UI while keeping each JPEG ~30-80KB.
    SCALE_WIDTH = 1280
    JPEG_QUALITY = 4 # ffmpeg -q:v (2=best … 31=worst); 4 is crisp + small

    class << self
      # Test seam: injectable command runner returning [stdout+stderr, status].
      attr_writer :runner

      def runner
        @runner ||= ->(cmd) { o, s = Open3.capture2e(*cmd); [o, s] }
      end

      def available?
        _out, status = runner.call(["ffmpeg", "-version"])
        status.respond_to?(:success?) ? status.success? : status.to_i.zero?
      rescue Errno::ENOENT
        false
      end
    end

    # timestamps: array of { seconds: Integer, label: String }. Returns the
    # frames it could extract (order preserved, failures skipped).
    def self.extract(video_path:, timestamps:)
      return [] if timestamps.blank?
      return [] unless available?

      timestamps.first(MAX_FRAMES).filter_map do |entry|
        seconds = entry[:seconds]
        next unless seconds.is_a?(Numeric) && seconds >= 0

        jpeg = extract_one(video_path, seconds)
        next if jpeg.blank?

        Frame.new(seconds: seconds.to_i, label: entry[:label].to_s, jpeg: jpeg)
      end
    end

    # Parse Gemini's "mm:ss" (or "hh:mm:ss", or bare seconds) into an integer
    # count of seconds. Returns nil for anything unparseable.
    def self.parse_timestamp(value)
      str = value.to_s.strip
      return nil if str.empty?

      if str.match?(/\A\d+\z/)
        return str.to_i
      end

      parts = str.split(":")
      return nil unless parts.size.between?(2, 3) && parts.all? { |p| p.match?(/\A\d+\z/) }

      parts.map(&:to_i).reduce(0) { |acc, part| acc * 60 + part }
    end

    def self.extract_one(video_path, seconds)
      Dir.mktmpdir("syrus-frame-") do |dir|
        out = File.join(dir, "frame.jpg")
        # Input-seek (-ss before -i) is fast; -frames:v 1 grabs a single frame;
        # scale caps width, -1 keeps aspect. Quiet + overwrite.
        cmd = [
          "ffmpeg", "-nostdin", "-loglevel", "error", "-y",
          "-ss", seconds.to_s, "-i", video_path,
          "-frames:v", "1",
          "-vf", "scale=#{SCALE_WIDTH}:-1",
          "-q:v", JPEG_QUALITY.to_s,
          out
        ]
        _output, status = runner.call(cmd)
        ok = status.respond_to?(:success?) ? status.success? : status.to_i.zero?
        return nil unless ok && File.exist?(out) && File.size(out).positive?

        File.binread(out)
      end
    rescue StandardError => error
      Rails.logger.warn("[Gemini::FrameExtractor] frame at #{seconds}s failed: #{error.class}: #{error.message}")
      nil
    end
  end
end
