class AdminAction < ApplicationRecord
  belongs_to :user
  serialize :params, coder: JSON

  validates :action, presence: true
  validates :performed_at, presence: true

  before_update { raise ActiveRecord::ReadOnlyRecord, "AdminAction is append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "AdminAction is append-only" unless destroyed_by_association }

  scope :recent, -> { order(performed_at: :desc).limit(50) }

  # Convenience: log an action against the current user. Caller
  # passes a symbol/string `action` and an optional params Hash
  # (gets JSON-encoded). Returns the persisted record so callers
  # can chain or assert on it in tests.
  def self.log!(user:, action:, params: {})
    create!(user: user, action: action.to_s, params: params, performed_at: Time.current)
  end
end
