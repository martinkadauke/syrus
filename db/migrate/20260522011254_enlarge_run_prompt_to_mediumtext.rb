class EnlargeRunPromptToMediumtext < ActiveRecord::Migration[8.1]
  # The default `t.text` on MySQL is TEXT (65 KB). The pr_comment
  # prompt now includes the full PR comment thread + prior agent
  # summaries + recent commit subjects, and the first prod request
  # on a chatty PR overflowed:
  #   ActiveRecord::ValueTooLong: Mysql2::Error: Data too long for
  #   column 'prompt' at row 1
  # Promote to MEDIUMTEXT (16 MB) — plenty of headroom for any
  # realistic conversation history, far cheaper than LONGTEXT and
  # better matched to actual prompt growth shape. SQLite ignores
  # the limit and treats this as plain TEXT (no upper bound), so
  # dev / test are unaffected.
  def up
    return unless adapter == :mysql

    change_column :runs, :prompt, :text, limit: 16.megabytes
  end

  def down
    return unless adapter == :mysql

    change_column :runs, :prompt, :text
  end

  private

  def adapter
    connection.adapter_name.downcase.include?("mysql") ? :mysql : :other
  end
end
