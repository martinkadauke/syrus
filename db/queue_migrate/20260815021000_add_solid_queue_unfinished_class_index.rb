class AddSolidQueueUnfinishedClassIndex < ActiveRecord::Migration[8.1]
  def change
    return unless table_exists?(:solid_queue_jobs)

    add_index :solid_queue_jobs,
      [ :class_name, :finished_at, :id ],
      name: "idx_solid_queue_jobs_class_finished_id",
      if_not_exists: true
  end
end
