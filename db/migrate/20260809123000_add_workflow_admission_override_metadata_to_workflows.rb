class AddWorkflowAdmissionOverrideMetadataToWorkflows < ActiveRecord::Migration[8.1]
  def up
    add_column :workflows, :workflow_admission_override_present, :boolean, default: false, null: false
    add_column :workflows, :workflow_admission_override_at, :datetime

    add_index :workflows,
      [ :workflow_admission_override_present, :workflow_admission_override_at, :updated_at, :id ],
      name: "idx_workflows_admission_override_recent",
      if_not_exists: true

    execute <<~SQL.squish
      UPDATE workflows
      SET workflow_admission_override_present = TRUE,
          workflow_admission_override_at = updated_at
      WHERE artifacts LIKE '%"workflow_admission_override"%'
    SQL
  end

  def down
    remove_index :workflows, name: "idx_workflows_admission_override_recent", if_exists: true
    remove_column :workflows, :workflow_admission_override_at, if_exists: true
    remove_column :workflows, :workflow_admission_override_present, if_exists: true
  end
end
