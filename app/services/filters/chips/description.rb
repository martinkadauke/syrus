module Filters
  module Chips
    class Description < StringColumn
      filter_name "description"
      label "Description"
      column :issue_body
    end
  end
end
