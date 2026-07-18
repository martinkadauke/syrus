class CreateGraderConclusions < ActiveRecord::Migration[8.1]
  def up
    create_table :grader_conclusions, if_not_exists: true do |t|
      t.bigint :repository_id, null: false
      t.bigint :job_id
      t.bigint :workflow_id
      t.bigint :step_id
      t.bigint :run_id
      t.string :commit_sha, null: false, limit: 64
      t.string :grader_fingerprint, null: false, limit: 64
      t.string :grader_name, null: false, limit: 128
      t.boolean :required
      t.string :status, null: false, limit: 32
      t.integer :exit_code
      t.float :duration_s
      t.boolean :timed_out, null: false, default: false
      t.string :log_path, limit: 1024
      t.bigint :log_bytes
      t.datetime :checked_at, null: false
      t.json :metadata

      t.timestamps
    end

    unless index_exists?(:grader_conclusions,
                         [ :repository_id, :commit_sha, :grader_fingerprint, :status ],
                         name: "idx_grader_conclusions_success_lookup")
      add_index :grader_conclusions,
                [ :repository_id, :commit_sha, :grader_fingerprint, :status ],
                name: "idx_grader_conclusions_success_lookup"
    end

    unless index_exists?(:grader_conclusions,
                         [ :repository_id, :grader_name, :status, :created_at ],
                         name: "idx_grader_conclusions_history_lookup")
      add_index :grader_conclusions,
                [ :repository_id, :grader_name, :status, :created_at ],
                name: "idx_grader_conclusions_history_lookup"
    end
    add_index :grader_conclusions, :workflow_id unless index_exists?(:grader_conclusions, :workflow_id)
    add_index :grader_conclusions, :run_id unless index_exists?(:grader_conclusions, :run_id)

    add_foreign_key :grader_conclusions, :repositories unless foreign_key_exists?(:grader_conclusions, :repositories)
    add_foreign_key :grader_conclusions, :jobs unless foreign_key_exists?(:grader_conclusions, :jobs)
    add_foreign_key :grader_conclusions, :workflows unless foreign_key_exists?(:grader_conclusions, :workflows)
    add_foreign_key :grader_conclusions, :steps unless foreign_key_exists?(:grader_conclusions, :steps)
    add_foreign_key :grader_conclusions, :runs unless foreign_key_exists?(:grader_conclusions, :runs)
  end

  def down
    drop_table :grader_conclusions, if_exists: true
  end
end
