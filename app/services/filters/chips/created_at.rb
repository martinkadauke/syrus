module Filters
  module Chips
    class CreatedAt < DateColumn
      filter_name "created_at"
      column :created_at
    end
  end
end
