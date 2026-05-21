class AddDetailsToSteps < ActiveRecord::Migration[8.1]
  # Step gains a kind-specific JSON details bag. Most Steps store
  # `{}`; grader Steps will store
  # `{ "name", "command", "description", "required", "timeout_minutes" }`
  # once the per-grader-Step architecture lands (Phase B). Future
  # Step kinds (adversarial reviews, etc.) extend the bag without
  # schema churn.
  #
  # MySQL 8 rejects defaults on JSON columns at migration time
  # (SQLite dev accepts them, hides the issue). Follow the
  # nullable→backfill→change_column_null pattern. Model gets an
  # after_initialize seed so new records carry `{}` even without
  # a DB default.
  def up
    unless column_exists?(:steps, :details)
      add_column :steps, :details, :json
      execute "UPDATE steps SET details = '{}' WHERE details IS NULL"
      change_column_null :steps, :details, false
    end
  end

  def down
    remove_column :steps, :details if column_exists?(:steps, :details)
  end
end
