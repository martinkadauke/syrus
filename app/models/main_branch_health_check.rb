class MainBranchHealthCheck < ApplicationRecord
  SOURCES = %w[ ci_poll grader_workflow concern_quorum ].freeze
  CONCLUSIVE_GRADER_HEALTH = %w[ healthy broken ].freeze
  SETTLED_CI_HEALTH = %w[ healthy broken not_configured ].freeze
  SETTLED_GRADER_HEALTH = %w[ healthy broken inconclusive ].freeze
  RETAIN_AFTER = 7.days

  belongs_to :repository
  belongs_to :workflow, optional: true

  validates :sha, presence: true
  validates :checked_at, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }

  scope :recent, -> { order(checked_at: :desc) }
  scope :pruneable, -> { where(checked_at: ..RETAIN_AFTER.ago) }

  def self.conclusive_grader_result_exists?(repository:, sha:)
    where(
      repository: repository,
      sha: sha,
      source: "grader_workflow",
      grader_health: CONCLUSIVE_GRADER_HEALTH
    ).exists?
  end

  def self.settled_ci_result_exists?(repository:, sha:)
    where(
      repository: repository,
      sha: sha,
      source: "ci_poll",
      ci_health: SETTLED_CI_HEALTH
    ).exists?
  end

  def self.settled_grader_result_exists?(repository:, sha:)
    where(
      repository: repository,
      sha: sha,
      source: "grader_workflow",
      grader_health: SETTLED_GRADER_HEALTH
    ).exists?
  end

  def self.record_ci_poll(repository:, sha:, ci_health:, ci_failed_checks: nil)
    existing = matching_check(
      repository: repository,
      sha: sha,
      source: "ci_poll",
      ci_health: ci_health,
      ci_failed_checks: ci_failed_checks
    )
    return existing if existing

    create!(
      repository: repository,
      sha: sha,
      checked_at: Time.current,
      ci_health: ci_health,
      grader_health: repository.grader_health,
      ci_failed_checks: ci_failed_checks,
      grader_failed_names: nil,
      source: "ci_poll"
    )
  end

  def self.record_grader_workflow(repository:, sha:, grader_health:, grader_failed_names: nil, workflow: nil)
    existing = matching_check(
      repository: repository,
      workflow: workflow,
      sha: sha,
      source: "grader_workflow",
      grader_health: grader_health,
      grader_failed_names: grader_failed_names
    )
    return existing if existing

    create!(
      repository: repository,
      workflow: workflow,
      sha: sha,
      checked_at: Time.current,
      ci_health: repository.ci_health,
      grader_health: grader_health,
      ci_failed_checks: nil,
      grader_failed_names: grader_failed_names,
      source: "grader_workflow"
    )
  end

  def self.record_concern_quorum(repository:, sha:, grader_failed_names: nil)
    create!(
      repository: repository,
      sha: sha,
      checked_at: Time.current,
      ci_health: repository.ci_health,
      grader_health: "broken",
      ci_failed_checks: nil,
      grader_failed_names: grader_failed_names,
      source: "concern_quorum"
    )
  end

  def self.matching_check(repository:, sha:, source:, workflow: nil, **attributes)
    scope = where(repository: repository, sha: sha, source: source)
    scope = scope.where(workflow: workflow) if source == "grader_workflow"
    scope.recent.limit(20).detect do |check|
      attributes.all? do |attribute, value|
        stored_value = check.public_send(attribute)
        json_payload_attribute?(attribute) ? json_payload_equal?(stored_value, value) : stored_value == value
      end
    end
  end
  private_class_method :matching_check

  def self.json_payload_attribute?(attribute)
    attribute.in?([ :ci_failed_checks, :grader_failed_names ])
  end
  private_class_method :json_payload_attribute?

  def self.json_payload_equal?(left, right)
    normalize_json_payload(left) == normalize_json_payload(right)
  end
  private_class_method :json_payload_equal?

  def self.normalize_json_payload(value)
    case value
    when nil
      []
    when Array
      value.map { |item| normalize_json_payload(item) }
    when Hash
      value.transform_keys(&:to_s).sort.to_h do |key, item|
        [ key, normalize_json_payload(item) ]
      end
    else
      value
    end
  end
  private_class_method :normalize_json_payload
end
