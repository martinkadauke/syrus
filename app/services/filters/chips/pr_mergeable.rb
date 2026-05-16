module Filters
  module Chips
    # Tri-state: true / false / nil ("unknown"). The is_set / is_unset
    # operators inherited from EnumColumn map "unknown" cleanly.
    class PrMergeable < EnumColumn
      filter_name "pr_mergeable"
      label "PR mergeable"
      column :pr_mergeable
      values "true", "false"
    end
  end
end
