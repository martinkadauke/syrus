class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :repositories, dependent: :destroy
  has_many :jobs, dependent: :destroy
  has_many :invitations, foreign_key: :invited_by_id, dependent: :nullify

  encrypts :claude_oauth_token
  encrypts :github_token

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  before_create :promote_first_user_to_admin

  def admin?
    admin
  end

  private

  def promote_first_user_to_admin
    self.admin = true if User.count.zero?
  end
end
