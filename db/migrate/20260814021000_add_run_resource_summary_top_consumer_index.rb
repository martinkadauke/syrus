class AddRunResourceSummaryTopConsumerIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :run_resource_summaries,
              [ :process_attributed_duration_seconds, :created_at ],
              name: "idx_run_resource_summaries_process_duration_created",
              if_not_exists: true
  end
end
