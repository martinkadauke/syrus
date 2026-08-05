class AddWorkflowAdmissionPolicyToAppSettings < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:app_settings, :workflow_admission_policy)
      add_column :app_settings, :workflow_admission_policy, :string, default: "whole_workflow", null: false
    end
  end
end
