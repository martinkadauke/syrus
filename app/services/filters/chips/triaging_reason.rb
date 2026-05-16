module Filters
  module Chips
    class TriagingReason < EnumColumn
      filter_name "triaging_reason"
      label "Triaging reason"
      column :triaging_reason
    end
  end
end
