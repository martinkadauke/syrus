# A narrated screen recording of the user testing their app, attached to a
# chat. Gemini extracts a structured account of everything shown/narrated
# (issues, summary, open questions); the analysis is then injected into the
# chat as a turn so the EXISTING chat agent can ask follow-ups or propose an
# Epic through the normal proposal machinery. Gemini is the eyes; the chat
# agent stays the brain.
class ChatVideoWalkthrough < ApplicationRecord
  STATES = %w[uploaded analyzing analyzed failed].freeze
  # MediaRecorder produces webm; drag-ins are commonly mp4/mov. All are
  # Gemini-supported natively, so no transcoding anywhere.
  ALLOWED_CONTENT_TYPES = %w[video/webm video/mp4 video/quicktime].freeze
  # 2 GB is Gemini's hard per-file cap; 500 MB keeps uploads snappy and is
  # ~25 minutes at the recorder profile — far beyond the duration gate.
  MAX_FILE_SIZE = 500.megabytes
  # Recorder + drag-in duration gate. Recordings at default media resolution
  # cost ~300 tokens/sec; the analysis job switches Gemini to low resolution
  # beyond 12 minutes so even a full 15-minute video fits free-tier windows.
  MAX_DURATION_SECONDS = 15 * 60

  belongs_to :chat_session
  belongs_to :user
  has_one_attached :file, dependent: :purge

  attribute :state, :string, default: "uploaded"

  validates :state, inclusion: { in: STATES }
  validates :content_type, inclusion: {
    in: ALLOWED_CONTENT_TYPES,
    message: "must be a webm, mp4, or QuickTime video"
  }
  validates :byte_size, numericality: {
    only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_FILE_SIZE
  }
  validates :duration_seconds, numericality: {
    only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_DURATION_SECONDS
  }, allow_nil: true
  # Only required at creation — the prune job purges the blob from settled
  # rows after a retention window, and re-delivery retries (analysis already
  # present) don't need the video, so a later update must not demand it.
  validate :file_attached, on: :create

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  STATES.each do |name|
    define_method("#{name}?") { state == name }
  end

  def analysis_summary
    analysis&.dig("summary").to_s
  end

  def analysis_issues
    Array(analysis&.dig("issues"))
  end

  def analysis_open_questions
    Array(analysis&.dig("open_questions"))
  end

  def display_title
    title.presence || "Walkthrough video"
  end

  private

  def file_attached
    errors.add(:file, "must be attached") unless file.attached?
  end
end
