require "fileutils"
require "zlib"

module SyrusSearchDatabaseTasks
  REQUIRED_TABLE_SQL = {
    "chat_message_fts" => <<~SQL,
      CREATE VIRTUAL TABLE IF NOT EXISTS chat_message_fts
      USING fts5(
        content,
        user_id UNINDEXED,
        chat_session_id UNINDEXED,
        chat_message_id UNINDEXED,
        role UNINDEXED,
        created_at UNINDEXED,
        tokenize = 'porter unicode61'
      )
    SQL
    "chat_search_metadata" => <<~SQL,
      CREATE TABLE IF NOT EXISTS chat_search_metadata (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    SQL
    "job_fts" => <<~SQL,
      CREATE VIRTUAL TABLE IF NOT EXISTS job_fts
      USING fts5(
        title,
        body,
        job_id UNINDEXED,
        user_id UNINDEXED,
        repository_id UNINDEXED,
        state UNINDEXED,
        created_at UNINDEXED,
        tokenize = 'porter unicode61'
      )
    SQL
    "epic_fts" => <<~SQL,
      CREATE VIRTUAL TABLE IF NOT EXISTS epic_fts
      USING fts5(
        title,
        description,
        epic_id UNINDEXED,
        user_id UNINDEXED,
        repository_id UNINDEXED,
        state UNINDEXED,
        created_at UNINDEXED,
        tokenize = 'porter unicode61'
      )
    SQL
    "test_case_fts" => <<~SQL,
      CREATE VIRTUAL TABLE IF NOT EXISTS test_case_fts
      USING fts5(
        name,
        suite_name,
        file_path,
        test_case_id UNINDEXED,
        user_id UNINDEXED,
        repository_id UNINDEXED,
        status UNINDEXED,
        created_at UNINDEXED,
        tokenize = 'porter unicode61'
      )
    SQL
    "operational_log_fts" => <<~SQL
      CREATE VIRTUAL TABLE IF NOT EXISTS operational_log_fts
      USING fts5(
        message,
        context_text,
        context_json UNINDEXED,
        operational_log_event_id UNINDEXED,
        occurred_at UNINDEXED,
        level UNINDEXED,
        role UNINDEXED,
        hostname UNINDEXED,
        app_revision UNINDEXED,
        pid UNINDEXED,
        source UNINDEXED,
        job_id UNINDEXED,
        workflow_id UNINDEXED,
        run_id UNINDEXED,
        request_id UNINDEXED,
        tokenize = 'porter unicode61'
      )
    SQL
  }.freeze

  module_function

  def prepare!
    SearchRecord.connection_pool.migration_context.migrate
    ensure_required_tables!
  end

  def ensure_required_tables!
    REQUIRED_TABLE_SQL.each do |table_name, sql|
      next if table_exists?(table_name)

      SearchRecord.connection.execute(sql)
    end
  end

  def table_exists?(table_name)
    SearchRecord.connection.select_value(
      "SELECT name FROM sqlite_master WHERE name = #{SearchRecord.connection.quote(table_name)}"
    ).present?
  end
end

namespace :syrus do
  desc "Create and migrate the local search database"
  task prepare_search: :environment do
    database_path = SearchRecord.connection_db_config.database
    if database_path.present? && database_path != ":memory:"
      FileUtils.mkdir_p(File.dirname(database_path))
      FileUtils.mkdir_p(Rails.root.join("tmp", "locks"))
      lock_path = Rails.root.join("tmp", "locks", "search-database-#{Zlib.crc32(database_path.to_s)}.lock")
      File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(File::LOCK_EX)
        SyrusSearchDatabaseTasks.prepare!
      ensure
        lock.flock(File::LOCK_UN) rescue nil
      end
    else
      SyrusSearchDatabaseTasks.prepare!
    end
  end
end
