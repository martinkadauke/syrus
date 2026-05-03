module Workflows
  # The "Resume" trigger — operator clicks Resume on a Run that
  # died mid-flight. Today this maps 1:1 with `Prompts::Resume`
  # passing `--resume <session_id>` to claude.
  #
  # In v1's linear-Step model the cleanest representation is: a
  # Resume Workflow has a single step kind "manual" (because it
  # really is "give the agent its prior context plus a continue
  # nudge and let it run"). The Step's Run gets parent_session_id
  # set to the dead Run's captured session, and Steps::Manual
  # threads `--resume` through.
  #
  # When v3 ships agent-authored DAGs, Resume gets richer — the
  # workflow could re-instantiate the failed step's downstream
  # chain on completion. v1 keeps it simple.
  class Resume < Base
    steps :manual

    def self.trigger_kind = "resume"
  end
end
