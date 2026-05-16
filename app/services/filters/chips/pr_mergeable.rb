module Filters
  module Chips
    # Tri-state: true / false / nil ("unknown"). The is_set / is_unset
    # operators inherited from EnumColumn map "unknown" cleanly.
    class PrMergeable < EnumColumn
      filter_name "pr_mergeable"
      column :pr_mergeable
    end
  end
end
