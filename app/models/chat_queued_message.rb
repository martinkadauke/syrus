class ChatQueuedMessage < ApplicationRecord
  belongs_to :chat_session

  after_commit :broadcast_chat_controls

  validates :content, presence: true
  validate :text_is_present

  scope :pending, -> { where(delivered_at: nil) }

  def text
    content.is_a?(Hash) ? content["text"].to_s : content.to_s
  end

  # A message that carries media (a walkthrough video or file/image attachments)
  # is valid with no text — the media IS the message. Only a bodyless, medialess
  # message is blank.
  def carries_media?
    return false unless content.is_a?(Hash)

    content["video_walkthrough_id"].present? || content["attachments"].present?
  end

  private

  def text_is_present
    return if carries_media?

    errors.add(:content, "can't be blank") if text.blank?
  end

  def broadcast_chat_controls
    chat_session.broadcast_controls
  end
end
