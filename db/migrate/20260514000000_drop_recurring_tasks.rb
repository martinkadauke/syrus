class DropRecurringTasks < ActiveRecord::Migration[8.1]
  # RecurringTask was a stripped-down sibling of ScheduledTask used only
  # by the chat agent's `schedule_recurring` MCP tool. Folded back into
  # ScheduledTask (chat tool now creates ScheduledTask with kind: cron),
  # so the dedicated table goes away. No data preservation — the per-
  # repo Scheduled Tasks tab now reads from `scheduled_tasks` directly.
  def up
    drop_table :recurring_tasks
  end

  def down
    create_table :recurring_tasks do |t|
      t.references :repository, null: false, foreign_key: false
      t.references :user,       null: false, foreign_key: false
      t.string  :label,           null: false
      t.string  :cron_expression, null: false
      t.text    :prompt,          null: false
      t.datetime :next_fire_at,   null: false
      t.boolean :enabled, default: true, null: false
      t.timestamps
    end
    add_index :recurring_tasks, [ :enabled, :next_fire_at ]
  end
end
