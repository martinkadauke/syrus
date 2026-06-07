class AddMergeabilityStateToJobs < ActiveRecord::Migration[8.1]
  COLUMNS = {
    github_mergeable: :boolean,
    github_mergeable_state: :string,
    mergeability_head_sha: :string,
    mergeability_base_sha: :string,
    mergeability_base_ref: :string,
    mergeability_checked_at: :datetime,
    local_mergeable: :boolean,
    local_mergeable_state: :string,
    local_mergeability_head_sha: :string,
    local_mergeability_base_sha: :string,
    local_mergeability_checked_at: :datetime
  }.freeze

  def up
    COLUMNS.each do |name, type|
      add_column :jobs, name, type unless column_exists?(:jobs, name)
    end
  end

  def down
    COLUMNS.keys.reverse_each do |name|
      remove_column :jobs, name if column_exists?(:jobs, name)
    end
  end
end
