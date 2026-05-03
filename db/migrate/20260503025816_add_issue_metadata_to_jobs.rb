class AddIssueMetadataToJobs < ActiveRecord::Migration[8.1]
  # Originally landed with timestamp 20260502060000, which collided
  # with AddLastHeartbeatAtToRuns (added concurrently on a different
  # branch). The duplicate broke local `db:test:prepare` —
  # ActiveRecord rejects two migration files with the same version.
  # Bumped to a fresh timestamp; guarded with column_exists? so that
  # production (where the original 20260502060000 file already ran)
  # re-applies it as a no-op when this version is processed.
  def change
    add_column :jobs, :issue_title, :string unless column_exists?(:jobs, :issue_title)
    add_column :jobs, :issue_body, :text    unless column_exists?(:jobs, :issue_body)
  end
end
