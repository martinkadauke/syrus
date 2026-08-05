class AddExternalPrUniqueIndexToJobs < ActiveRecord::Migration[8.1]
  def up
    clear_duplicate_external_pr_links!

    unless index_exists?(:jobs, [:repository_id, :external_pr_number], name: "index_jobs_on_repository_id_and_external_pr_number_unique")
      add_index :jobs, [:repository_id, :external_pr_number],
                unique: true,
                name: "index_jobs_on_repository_id_and_external_pr_number_unique"
    end
  end

  def down
    remove_index :jobs, name: "index_jobs_on_repository_id_and_external_pr_number_unique",
                 if_exists: true
  end

  private

  def clear_duplicate_external_pr_links!
    duplicate_groups = select_all(<<~SQL.squish).to_a
      SELECT repository_id, external_pr_number
      FROM jobs
      WHERE external_pr_number IS NOT NULL
      GROUP BY repository_id, external_pr_number
      HAVING COUNT(*) > 1
    SQL

    duplicate_groups.each do |group|
      rows = select_all(sanitize_sql_array([
        <<~SQL.squish,
          SELECT id, kind, state, closure_reason, created_at
          FROM jobs
          WHERE repository_id = ? AND external_pr_number = ?
          ORDER BY id ASC
        SQL
        group["repository_id"],
        group["external_pr_number"]
      ])).to_a

      keeper = rows.min_by { |row| external_pr_link_rank(row) }
      duplicate_ids = rows.map { |row| row["id"] } - [ keeper["id"] ]
      next if duplicate_ids.empty?

      execute(<<~SQL.squish)
        UPDATE jobs
        SET external_pr_number = NULL
        WHERE id IN (#{duplicate_ids.map { |id| quote(id) }.join(", ")})
      SQL
    end
  end

  def external_pr_link_rank(row)
    [
      row["kind"] == "external_pr" ? 0 : 1,
      row["state"] != "closed" ? 0 : 1,
      row["closure_reason"] == "external_pr_merged" ? 0 : 1,
      row["created_at"] || Time.at(0),
      row["id"]
    ]
  end

  def sanitize_sql_array(array)
    ActiveRecord::Base.sanitize_sql_array(array)
  end
end
