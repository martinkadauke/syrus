class AddTelegramSettingsToAppSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :app_settings, :telegram_bot_token, :text unless column_exists?(:app_settings, :telegram_bot_token)
    add_column :app_settings, :telegram_update_offset, :integer, default: 0 unless column_exists?(:app_settings, :telegram_update_offset)
  end

  def down
    remove_column :app_settings, :telegram_bot_token if column_exists?(:app_settings, :telegram_bot_token)
    remove_column :app_settings, :telegram_update_offset if column_exists?(:app_settings, :telegram_update_offset)
  end
end
