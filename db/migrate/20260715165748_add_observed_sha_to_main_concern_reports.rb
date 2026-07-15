class AddObservedShaToMainConcernReports < ActiveRecord::Migration[8.1]
  def up
    add_column :main_concern_reports, :observed_sha, :string unless column_exists?(:main_concern_reports, :observed_sha)
  end

  def down
    remove_column :main_concern_reports, :observed_sha if column_exists?(:main_concern_reports, :observed_sha)
  end
end
