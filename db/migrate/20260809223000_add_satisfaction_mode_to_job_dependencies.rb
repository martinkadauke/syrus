class AddSatisfactionModeToJobDependencies < ActiveRecord::Migration[8.1]
  CLEANUP_GATE_TITLE = "Remove standalone Epic reconciliation special casing after remaining reconciliation jobs close".freeze
  CLEANUP_GATE_BODY_PATTERN = "%remaining reconciliation Jobs%landed%canceled%closed%".freeze

  def up
    unless column_exists?(:job_dependencies, :satisfaction_mode)
      add_column :job_dependencies, :satisfaction_mode, :string, null: false, default: "success"
    end

    cleanup_job_ids = select_values(<<~SQL.squish)
      SELECT id
      FROM jobs
      WHERE issue_title = #{quote(CLEANUP_GATE_TITLE)}
         OR issue_body LIKE #{quote(CLEANUP_GATE_BODY_PATTERN)}
    SQL

    return if cleanup_job_ids.empty?

    execute(<<~SQL.squish)
      UPDATE job_dependencies
      SET satisfaction_mode = 'closed'
      WHERE job_id IN (#{cleanup_job_ids.join(",")})
        AND source = 'manual'
    SQL
  end

  def down
    remove_column :job_dependencies, :satisfaction_mode if column_exists?(:job_dependencies, :satisfaction_mode)
  end
end
