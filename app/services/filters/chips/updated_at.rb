module Filters
  module Chips
    class UpdatedAt < DateColumn
      filter_name "updated_at"
      label "Updated"
      column :updated_at
    end
  end
end
