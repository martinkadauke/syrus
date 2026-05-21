module Filters
  module Chips
    # Namespace anchor for spawned-process chips. The actual chip
    # classes (State, Kind, Hostname, RunId, WorkflowId, Stale) live
    # in the per-file siblings under spawned_processes/. This file
    # just defines the module — see admin_queue.rb / admin_users.rb
    # for the same eager-load duplication story.
    module SpawnedProcesses
    end
  end
end
