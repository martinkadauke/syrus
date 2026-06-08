class AddMergeTrainSettingsToAppSettings < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:app_settings, :merge_train_enabled)
      add_column :app_settings, :merge_train_enabled, :boolean, default: false, null: false
    end
    unless column_exists?(:app_settings, :merge_train_max_size)
      add_column :app_settings, :merge_train_max_size, :integer, default: 20, null: false
    end
  end

  def down
    remove_column :app_settings, :merge_train_enabled if column_exists?(:app_settings, :merge_train_enabled)
    remove_column :app_settings, :merge_train_max_size if column_exists?(:app_settings, :merge_train_max_size)
  end
end
