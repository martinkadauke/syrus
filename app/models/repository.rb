class Repository < ApplicationRecord
  GITHUB_NAME = /\A[a-zA-Z0-9](?:[a-zA-Z0-9._-]*[a-zA-Z0-9])?\z/

  belongs_to :user
  has_many :jobs, dependent: :destroy

  validates :owner, presence: true, format: { with: GITHUB_NAME }
  validates :name, presence: true, format: { with: GITHUB_NAME }
  validates :default_branch, presence: true
  validates :trigger_label, presence: true
  validates :owner, uniqueness: { scope: [ :user_id, :name ], case_sensitive: false }

  def slug
    "#{owner}/#{name}"
  end
end
