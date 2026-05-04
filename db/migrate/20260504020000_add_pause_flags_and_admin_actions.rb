class AddPauseFlagsAndAdminActions < ActiveRecord::Migration[8.1]
  # Two pieces:
  #
  # 1. Pause flags on app_settings — global kill switches the
  #    operator console flips. Polling jobs and RunJob pre-flight
  #    against these and short-circuit / re-enqueue when set.
  #
  # 2. admin_actions audit table — every operator-console
  #    intervention (pause polling, force reap, clear GH cache,
  #    etc.) lands a row here so we can answer "who did what,
  #    when?" after the fact. Append-only by convention.
  def change
    change_table :app_settings do |t|
      t.boolean :polling_paused, default: false, null: false
      t.boolean :runs_paused,    default: false, null: false
    end

    create_table :admin_actions do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :action, null: false
      t.text :params      # JSON-encoded parameter blob (optional)
      t.datetime :performed_at, null: false
      t.timestamps
      t.index :performed_at
    end
  end
end
