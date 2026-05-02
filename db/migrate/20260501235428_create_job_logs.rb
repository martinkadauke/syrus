class CreateJobLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :job_logs do |t|
      t.references :job, null: false, foreign_key: true
      t.text :chunk, null: false
      t.integer :sequence, null: false

      t.timestamps
    end

    add_index :job_logs, [ :job_id, :sequence ], unique: true
  end
end
