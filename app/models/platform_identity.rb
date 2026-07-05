class PlatformIdentity < ApplicationRecord
  PLATFORMS = %w[ telegram slack ].freeze

  belongs_to :user

  enum :platform, PLATFORMS.index_with(&:itself), validate: true

  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :external_id, presence: true
  validates :linked_at, presence: true
  validates :external_id, uniqueness: { scope: :platform, message: "is already linked to a Syrus account" }
end
