class AddCleanedUpAtToWorkflows < ActiveRecord::Migration[8.1]
  # Stamped by WorkflowWorkspace.cleanup_for whenever the workflow's
  # disk workspace is torn down. Lets the UI know whether a "Retry
  # from failed step" is still possible: if cleaned_up_at is nil
  # the workspace is still on the PVC and a retry can pick up where
  # the failed step left off (committed work intact, --resume
  # threading available); if it's stamped, the workspace is gone
  # and the operator should Replay from the top instead.
  #
  # Indexed for WorkflowWorkspacePruneJob's daily scan, which
  # filters terminal workflows with cleaned_up_at IS NULL whose
  # finished_at is older than the retention window.
  def change
    add_column :workflows, :cleaned_up_at, :datetime
    add_index  :workflows, :cleaned_up_at
  end
end
