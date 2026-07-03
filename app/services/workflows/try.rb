module Workflows
  # Declares a Step with typed failure branches. Base materializes only the
  # happy-path Step up front; StepDispatcher inserts the matching branch if the
  # Step fails with a declared failure code.
  class Try
    attr_reader :step_kind, :failure_branches, :id

    def initialize(step)
      @step_kind = step.to_s
      @failure_branches = {}
      @id = SecureRandom.uuid
    end

    def try? = true

    def on_failure(code, branch)
      @failure_branches[code.to_s] = Workflows::Base.normalize_chain_template(Array(branch))
      self
    end

    def step_kinds
      [ step_kind ]
    end

    def to_chain_template
      {
        "type" => "try",
        "id" => id,
        "step" => step_kind,
        "on_failure" => failure_branches.transform_values do |nodes|
          Workflows::Base.serialize_chain_template(nodes)
        end
      }
    end
  end
end
