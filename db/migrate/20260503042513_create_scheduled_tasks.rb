class CreateScheduledTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_tasks do |t|
      t.references :repository, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :prompt, null: false
      t.string :kind, null: false                     # "cron" | "one_shot"
      t.string :cron_expression                       # set when kind=cron
      t.datetime :fire_at                             # set when kind=one_shot
      t.integer :minute_offset, null: false, default: 0  # 0..59, seeded random per cron task
      t.string :pr_pileup_policy, null: false, default: "skip"  # "skip" | "pile" | "replace"
      # state values:
      #   scheduled    — firing as configured
      #   paused       — operator-paused (won't fire)
      #   auto_paused  — paused after consecutive_failure_count hit the cap
      #   fired        — one_shot completed (terminal for kind=one_shot)
      t.string :state, null: false, default: "scheduled"
      t.integer :consecutive_failure_count, null: false, default: 0
      t.datetime :last_fired_at
      t.datetime :last_successful_fire_at
      t.datetime :archived_at                         # soft delete
      t.timestamps
      t.index :archived_at
      t.index [ :state, :archived_at ]
    end

    # Cron Jobs spawn from a ScheduledTask but otherwise reuse the
    # existing Job pipeline (worktree, branch, PR, closure, polling).
    # `kind` discriminates them at the model layer; `scheduled_task_id`
    # links back to the spawning task. issue_number is now nullable so
    # cron Jobs (which have no issue) can still validate cleanly.
    add_column :jobs, :kind, :string, null: false, default: "issue"
    add_reference :jobs, :scheduled_task, null: true, foreign_key: true, index: true
    change_column_null :jobs, :issue_number, true
  end
end
