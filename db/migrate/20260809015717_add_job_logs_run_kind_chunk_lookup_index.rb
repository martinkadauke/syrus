class AddJobLogsRunKindChunkLookupIndex < ActiveRecord::Migration[8.1]
  INDEX_NAME = "idx_job_logs_run_kind_chunk_lookup"

  def up
    return unless table_exists?(:job_logs)
    return if index_exists?(:job_logs, [ :run_id, :kind, :chunk ], name: INDEX_NAME)

    add_index :job_logs,
              [ :run_id, :kind, :chunk ],
              name: INDEX_NAME,
              length: { chunk: 191 }
  end

  def down
    return unless table_exists?(:job_logs)

    remove_index :job_logs, name: INDEX_NAME if index_exists?(:job_logs, name: INDEX_NAME)
  end
end
