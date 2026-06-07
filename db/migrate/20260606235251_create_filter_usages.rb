class CreateFilterUsages < ActiveRecord::Migration[8.1]
  def up
    create_table :filter_usages, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :surface, null: false
      t.string :subject, null: false
      t.string :fingerprint, null: false
      t.string :label, null: false
      t.json :filter_node, null: false
      t.integer :use_count, null: false, default: 0
      t.datetime :last_used_at, null: false

      t.timestamps
    end

    unless index_exists?(:filter_usages, [ :user_id, :surface, :subject, :fingerprint ], name: "index_filter_usages_on_user_surface_subject_fingerprint")
      add_index :filter_usages,
                [ :user_id, :surface, :subject, :fingerprint ],
                unique: true,
                name: "index_filter_usages_on_user_surface_subject_fingerprint"
    end

    unless index_exists?(:filter_usages, [ :user_id, :surface, :subject, :last_used_at ], name: "index_filter_usages_on_user_surface_subject_recent")
      add_index :filter_usages,
                [ :user_id, :surface, :subject, :last_used_at ],
                name: "index_filter_usages_on_user_surface_subject_recent"
    end
  end

  def down
    drop_table :filter_usages, if_exists: true
  end
end
