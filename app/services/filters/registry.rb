module Filters
  class UnknownFilterField < ArgumentError
    def initialize(field)
      super("unknown filter field: #{field.inspect}")
    end
  end

  # Central index of every chip type the system knows about. Adding a
  # new filter is a one-line entry here plus a class under
  # Filters::Chips. Bucket / operator vocabulary lives on the chip
  # class itself (`bucket`, `operators` DSL).
  class Registry
    CHIPS = {
      # Thread / metadata
      "state"                         => "Filters::Chips::State",
      "kind"                          => "Filters::Chips::Kind",
      "priority"                      => "Filters::Chips::Priority",
      "agent_provider"                => "Filters::Chips::AgentProvider",
      "closure_reason"                => "Filters::Chips::ClosureReason",
      "triaging_reason"               => "Filters::Chips::TriagingReason",
      "validity"                      => "Filters::Chips::Validity",

      # Latest-X derivations
      "latest_workflow_state"         => "Filters::Chips::LatestWorkflowState",
      "latest_workflow_trigger_kind"  => "Filters::Chips::LatestWorkflowTriggerKind",
      "latest_run_state"              => "Filters::Chips::LatestRunState",

      # PR-related
      "pr_present"                    => "Filters::Chips::PrPresent",
      "pr_mergeable"                  => "Filters::Chips::PrMergeable",

      # FKs
      "repository_id"                 => "Filters::Chips::RepositoryId",
      "epic_id"                       => "Filters::Chips::EpicId",
      "parent_job_id"                 => "Filters::Chips::ParentJobId",

      # Strings (free-text)
      "title"                         => "Filters::Chips::Title",
      "description"                   => "Filters::Chips::Description",
      "branch_name"                   => "Filters::Chips::BranchName",
      "pr_title"                      => "Filters::Chips::PrTitle",

      # Numbers
      "issue_number"                  => "Filters::Chips::IssueNumber",
      "pr_number"                     => "Filters::Chips::PrNumber",

      # Dates
      "age"                           => "Filters::Chips::Age",
      "created_at"                    => "Filters::Chips::CreatedAt",
      "updated_at"                    => "Filters::Chips::UpdatedAt",
      "finished_at"                   => "Filters::Chips::FinishedAt",
      "last_seen_comment_at"          => "Filters::Chips::LastSeenCommentAt",

      # Booleans (predicates)
      "pinned_by_me"                  => "Filters::Chips::PinnedByMe",
      "has_unread_feedback"           => "Filters::Chips::HasUnreadFeedback",
      "has_active_run"                => "Filters::Chips::HasActiveRun",
      "has_blocked_deps"              => "Filters::Chips::HasBlockedDeps",
      "has_parent_job"                => "Filters::Chips::HasParentJob",
      "has_child_jobs"                => "Filters::Chips::HasChildJobs",

      # Collection
      "tags"                          => "Filters::Chips::Tags",

      # Preset macro (composite)
      "attention"                     => "Filters::Chips::Attention"
    }.freeze

    def self.find(field)
      class_name = CHIPS[field.to_s] or raise UnknownFilterField.new(field)
      class_name.constantize
    end

    def self.fields
      CHIPS.keys
    end

    def self.exists?(field)
      CHIPS.key?(field.to_s)
    end
  end
end
