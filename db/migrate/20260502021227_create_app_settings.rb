class CreateAppSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :app_settings do |t|
      t.boolean :signups_open, null: false, default: false

      t.timestamps
    end
  end
end
