class ChatContextCheckpoint < ApplicationRecord
  belongs_to :chat_session

  validates :compacted_through_message_id, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :source_message_count, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :summary_version, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :summary, presence: true

  scope :ordered, -> { order(compacted_through_message_id: :asc, id: :asc) }
  scope :latest_first, -> { order(compacted_through_message_id: :desc, id: :desc) }
end
