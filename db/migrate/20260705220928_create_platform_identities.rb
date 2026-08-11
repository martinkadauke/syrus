class CreatePlatformIdentities < ActiveRecord::Migration[8.1]
  def up
    create_table :platform_identities, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :external_id, null: false
      t.string :external_handle
      t.datetime :linked_at, null: false

      t.timestamps
    end

    unless index_exists?(:platform_identities, [ :platform, :external_id ])
      add_index :platform_identities, [ :platform, :external_id ], unique: true
    end
  end

  def down
    drop_table :platform_identities, if_exists: true
  end
end
