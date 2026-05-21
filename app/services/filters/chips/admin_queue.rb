module Filters
  module Chips
    # Namespace anchor for admin-queue chips. The actual chip classes
    # (QueueName, JobClass, FailedSince) live in the per-file siblings
    # under admin_queue/. This file just defines the module — having
    # the chip definitions ALSO inline here caused a superclass-mismatch
    # eager-load crash in production (both files defined `QueueName`
    # with different superclasses; Zeitwerk's lazy autoload in dev hid
    # it, eager_load tripped on the second definition).
    module AdminQueue
    end
  end
end
