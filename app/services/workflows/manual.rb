module Workflows
  # Operator-triggered freeform run with no pre-defined phases.
  # Single step, kind: manual; carries whatever prompt the operator
  # specified. The handler is generic: spawn claude with the
  # prompt, capture artifacts, done. No PR opening — manual runs
  # are exploratory by nature; the operator chooses what to do
  # with the result.
  class Manual < Base
    steps :manual

    def self.trigger_kind = "manual"
  end
end
