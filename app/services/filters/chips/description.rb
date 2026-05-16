module Filters
  module Chips
    class Description < StringColumn
      filter_name "description"
      column :issue_body
    end
  end
end
