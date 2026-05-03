class CreateClaudeSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :claude_sessions do |t|
      t.references :run, null: false, foreign_key: true, index: { unique: true }
      t.string :session_id, null: false
      t.text :transcript_jsonl, limit: 64.megabytes  # MEDIUMTEXT in MySQL
      t.timestamps
    end
    add_index :claude_sessions, :created_at  # for daily prune scan
  end
end
