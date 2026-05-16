module Filters
  module Chips
    class PrNumber < NumberColumn
      filter_name "pr_number"
      label "PR number"
      column :pr_number
    end
  end
end
