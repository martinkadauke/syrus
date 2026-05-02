class CreateJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :jobs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :repository, null: false, foreign_key: true
      t.integer :issue_number, null: false
      t.string :state, null: false, default: "queued"
      t.string :branch_name
      t.integer :pr_number
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :jobs, [ :repository_id, :state ]
    add_index :jobs, [ :repository_id, :issue_number, :state ]
  end
end
