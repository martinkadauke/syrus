module Filters
  module Chips
    class UpdatedAt < DateColumn
      filter_name "updated_at"
      column :updated_at
    end
  end
end
