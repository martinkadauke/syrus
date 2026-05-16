module Filters
  module Chips
    class Title < StringColumn
      filter_name "title"
      column :issue_title
    end
  end
end
