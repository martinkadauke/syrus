class CreateMergeTrains < ActiveRecord::Migration[8.1]
  def up
    unless table_exists?(:merge_trains)
      create_table :merge_trains do |t|
        t.references :epic, null: false, foreign_key: true, index: true
        t.references :repository, null: false, foreign_key: true, index: true
        t.string :base_branch, null: false
        t.string :state, null: false, default: "building"
        t.string :integration_branch
        t.string :integration_sha
        t.string :failure_reason, limit: 500
        t.datetime :finished_at
        t.timestamps
      end
    end

    unless table_exists?(:merge_train_members)
      create_table :merge_train_members do |t|
        t.references :merge_train, null: false, foreign_key: true, index: true
        t.references :job, null: false, foreign_key: true, index: true
        t.integer :position, null: false, default: 0
        t.string :state, null: false, default: "included"
        t.string :reason, limit: 500
        t.timestamps
      end
      add_index :merge_train_members, [ :merge_train_id, :position ]
      add_index :merge_train_members, [ :merge_train_id, :job_id ], unique: true
    end
  end

  def down
    drop_table :merge_train_members if table_exists?(:merge_train_members)
    drop_table :merge_trains if table_exists?(:merge_trains)
  end
end
