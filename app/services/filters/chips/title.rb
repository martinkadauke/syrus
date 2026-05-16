module Filters
  module Chips
    class Title < StringColumn
      filter_name "title"
      label "Title"
      column :issue_title
    end
  end
end
