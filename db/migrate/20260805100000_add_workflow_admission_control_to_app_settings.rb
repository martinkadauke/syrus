class AddWorkflowAdmissionControlToAppSettings < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:app_settings, :workflow_admission_control_enabled)
      add_column :app_settings, :workflow_admission_control_enabled, :boolean, default: true, null: false
    end

    unless column_exists?(:app_settings, :workflow_admission_control_changed_at)
      add_column :app_settings, :workflow_admission_control_changed_at, :datetime
    end

    unless column_exists?(:app_settings, :workflow_admission_control_changed_by_user_id)
      add_reference :app_settings,
                    :workflow_admission_control_changed_by_user,
                    foreign_key: { to_table: :users },
                    index: { name: "idx_app_settings_workflow_admission_changed_by" }
    end
  end
end
