module Filters
  module Chips
    module Epics
      class HasOpenChildren < BooleanExists
        filter_name "has_open_children"
        label "Has open children"

        def apply
          # "Open" used to be a literal AASM state; post-audit, the
          # equivalent is "any non-closed state." Mirror Job.open_threads
          # which excludes only :closed.
          apply_exists("EXISTS (SELECT 1 FROM jobs WHERE jobs.epic_id = epics.id AND jobs.state != ?)", "closed")
        end
      end
    end
  end
end
