class CreateRepositories < ActiveRecord::Migration[8.1]
  def change
    create_table :repositories do |t|
      t.references :user, null: false, foreign_key: true
      t.string :owner, null: false
      t.string :name, null: false
      t.string :default_branch, null: false, default: "main"
      t.boolean :polling_enabled, null: false, default: false
      t.string :trigger_label, null: false, default: "syrus"

      t.timestamps
    end

    add_index :repositories, [ :user_id, :owner, :name ], unique: true
  end
end
