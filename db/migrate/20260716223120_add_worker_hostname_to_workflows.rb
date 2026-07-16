class AddWorkerHostnameToWorkflows < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:workflows, :worker_hostname)
      add_column :workflows, :worker_hostname, :string
    end
  end

  def down
    if column_exists?(:workflows, :worker_hostname)
      remove_column :workflows, :worker_hostname
    end
  end
end
