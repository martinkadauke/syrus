class CreateRunDiagnostics < ActiveRecord::Migration[8.1]
  def change
    create_table :run_diagnostics do |t|
      t.references :run, null: false, foreign_key: true, index: { unique: true }

      # Exception that landed in RunJob's rescue StandardError.
      t.string :error_class, null: false
      t.text   :error_message
      t.text   :error_backtrace

      # JSON blobs (serialized via the model). Each captures a single
      # snapshot taken at the moment of failure — *before* worktree
      # cleanup — so the operator can see what the world looked like
      # when the Run blew up, even after the worktree is gone.
      t.text :git_snapshot          # status, log, branches, config in the worktree
      t.text :environment_snapshot  # filtered env vars (allowlisted)
      t.text :repo_snapshot         # repo metadata, branch, head_sha, pr_number etc.

      t.timestamps
      t.index :created_at  # for the prune scan
    end
  end
end
