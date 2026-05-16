module Filters
  module Chips
    class EpicId < FkColumn
      filter_name "epic_id"
      column :epic_id
    end
  end
end
