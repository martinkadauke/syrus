class Invitation < ApplicationRecord
  DEFAULT_TTL = 7.days

  belongs_to :invited_by, class_name: "User"

  has_secure_token :token

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :expires_at, presence: true

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

  before_validation :set_default_expiry, on: :create

  def accept!
    update!(accepted_at: Time.current)
  end

  def accepted?
    accepted_at.present?
  end

  def expired?
    expires_at <= Time.current
  end

  def usable?
    !accepted? && !expired?
  end

  private

  def set_default_expiry
    self.expires_at ||= DEFAULT_TTL.from_now
  end
end
