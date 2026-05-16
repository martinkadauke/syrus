module Filters
  module Chips
    class CreatedAt < DateColumn
      filter_name "created_at"
      label "Created"
      column :created_at
    end
  end
end
