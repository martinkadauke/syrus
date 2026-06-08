class MergeTrainMember < ApplicationRecord
  STATES = %w[ included merged failed ].freeze

  belongs_to :merge_train
  belongs_to :job

  validates :state, inclusion: { in: STATES }
  validates :position, presence: true
end
