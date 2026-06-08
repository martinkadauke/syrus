class MergeTrain < ApplicationRecord
  # An attempt to land an Epic's children together: build one
  # integration branch, grade it once, and land it atomically. See
  # docs/plans/landing-merge-train.md.
  STATES = %w[ building grading landing succeeded failed cancelled ].freeze
  TERMINAL_STATES = %w[ succeeded failed cancelled ].freeze

  belongs_to :epic
  belongs_to :repository
  has_many :members, -> { order(:position) }, class_name: "MergeTrainMember", dependent: :destroy, inverse_of: :merge_train

  has_many :jobs, through: :members

  validates :base_branch, presence: true
  validates :state, inclusion: { in: STATES }

  scope :active, -> { where.not(state: TERMINAL_STATES) }

  def member_jobs
    members.includes(:job).map(&:job)
  end

  def terminal?
    TERMINAL_STATES.include?(state)
  end
end
