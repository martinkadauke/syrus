class AddTreatGraderTimeoutsAsFailuresToRepositories < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:repositories, :treat_grader_timeouts_as_failures)
      add_column :repositories, :treat_grader_timeouts_as_failures, :boolean, null: false, default: false
    end
  end

  def down
    if column_exists?(:repositories, :treat_grader_timeouts_as_failures)
      remove_column :repositories, :treat_grader_timeouts_as_failures
    end
  end
end
