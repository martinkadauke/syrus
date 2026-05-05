class Repository < ApplicationRecord
  GITHUB_NAME = /\A[a-zA-Z0-9](?:[a-zA-Z0-9._-]*[a-zA-Z0-9])?\z/

  attribute :polling_enabled, :boolean, default: true

  belongs_to :user
  has_many :jobs, dependent: :destroy
  has_many :scheduled_tasks, dependent: :destroy

  validates :owner, presence: true, format: { with: GITHUB_NAME }
  validates :name, presence: true, format: { with: GITHUB_NAME }
  validates :default_branch, presence: true
  validates :trigger_label, presence: true
  validates :owner, uniqueness: { scope: [ :user_id, :name ], case_sensitive: false }

  # Default scope hides archived repos from every Repository.all /
  # User#repositories / Job.joins(:repository) call. The trade-off
  # (admin paths need to opt out) was discussed and accepted. Two
  # opt-out mechanisms:
  #
  #   - `Repository.archived`        — only archived (unscope first
  #                                    so the default doesn't fight
  #                                    the where clause)
  #   - `Repository.with_archived`   — both states; for admin /
  #                                    diagnostic surfaces that need
  #                                    to see the full population.
  #
  # `belongs_to :repository` declarations on associated models
  # (Job, ScheduledTask, Workflow→job→repository) are scoped to
  # `-> { unscoped }` so reaching from a Job back to its repo
  # resolves regardless of archive state — otherwise admin pages
  # for jobs whose repo got archived would 404.
  default_scope { where(archived_at: nil) }

  scope :active,        -> { where(archived_at: nil) }
  scope :archived,      -> { unscope(where: :archived_at).where.not(archived_at: nil) }
  scope :with_archived, -> { unscope(where: :archived_at) }

  def archived?
    archived_at.present?
  end

  # Mark the repo as done. Side-effect: also flips polling_enabled off so
  # that *if* someone unarchives later, polling stays off until they
  # explicitly re-enable it (re-enabling polling is a deliberate act, not
  # something that should silently rehydrate from a stale flag).
  def archive!
    update!(archived_at: Time.current, polling_enabled: false)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def slug
    "#{owner}/#{name}"
  end

  # Anonymous URL — safe to bake into a saved clone's remote.
  def remote_url
    "https://github.com/#{owner}/#{name}.git"
  end

  # Token-bearing URL used for push only. Constructed per-call so the token
  # never lives on disk inside .git/config.
  def authenticated_push_url(token)
    "https://x-access-token:#{token}@github.com/#{owner}/#{name}.git"
  end
end
