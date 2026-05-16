class AddApprovalStateToJobs < ActiveRecord::Migration[8.1]
  # Idempotent — a previous deploy attempt added `approved_at` but
  # crashed before recording the version in schema_migrations, so on
  # retry the bare `add_column :approved_at` died with
  # `Mysql2::Error: Duplicate column name`. Guard every column so
  # partial state from a previous failed run finishes cleanly.
  def up
    add_column :jobs, :approved_at, :datetime unless column_exists?(:jobs, :approved_at)
    add_column :jobs, :approved_via, :string unless column_exists?(:jobs, :approved_via)
    add_reference :jobs, :approved_by_user, null: true, foreign_key: { to_table: :users } unless column_exists?(:jobs, :approved_by_user_id)
    add_column :jobs, :approval_evidence, :json, default: {}, null: false unless column_exists?(:jobs, :approval_evidence)
  end

  def down
    remove_column :jobs, :approval_evidence if column_exists?(:jobs, :approval_evidence)
    remove_reference :jobs, :approved_by_user if column_exists?(:jobs, :approved_by_user_id)
    remove_column :jobs, :approved_via if column_exists?(:jobs, :approved_via)
    remove_column :jobs, :approved_at if column_exists?(:jobs, :approved_at)
  end
end
