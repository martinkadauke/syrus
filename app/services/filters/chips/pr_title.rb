module Filters
  module Chips
    class PrTitle < StringColumn
      filter_name "pr_title"
      label "PR title"
      column :pr_title
    end
  end
end
