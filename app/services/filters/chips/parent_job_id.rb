module Filters
  module Chips
    class ParentJobId < FkColumn
      filter_name "parent_job_id"
      label "Parent job"
      column :parent_job_id
    end
  end
end
