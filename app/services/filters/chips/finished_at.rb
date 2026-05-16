module Filters
  module Chips
    class FinishedAt < DateColumn
      filter_name "finished_at"
      label "Finished"
      column :finished_at
    end
  end
end
