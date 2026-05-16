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
      "state"                 => "Filters::Chips::State",
      "kind"                  => "Filters::Chips::Kind",
      "repository_id"         => "Filters::Chips::RepositoryId",
      "pr_present"            => "Filters::Chips::PrPresent",
      "age"                   => "Filters::Chips::Age",
      "tags"                  => "Filters::Chips::Tags",
      "attention"             => "Filters::Chips::Attention",
      "latest_workflow_state" => "Filters::Chips::LatestWorkflowState"
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
