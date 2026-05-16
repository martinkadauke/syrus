module Filters
  module Chips
    class BranchName < StringColumn
      filter_name "branch_name"
      column :branch_name
    end
  end
end
