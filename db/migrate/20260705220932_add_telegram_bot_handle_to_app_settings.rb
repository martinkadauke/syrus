class AddTelegramBotHandleToAppSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :app_settings, :telegram_bot_handle, :string unless column_exists?(:app_settings, :telegram_bot_handle)
  end

  def down
    remove_column :app_settings, :telegram_bot_handle if column_exists?(:app_settings, :telegram_bot_handle)
  end
end
