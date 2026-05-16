module Filters
  module Chips
    class IssueNumber < NumberColumn
      filter_name "issue_number"
      column :issue_number
    end
  end
end
