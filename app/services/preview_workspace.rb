require "fileutils"

class PreviewWorkspace
  def self.data_root
    Pathname.new(ENV["SYRUS_DATA_ROOT"] || File.expand_path("~/.syrus"))
  end

  def self.path_for(preview_environment)
    data_root.join("previews", preview_environment.id.to_s)
  end

  def self.prepare!(preview_environment, git: GitRunner.new)
    new(preview_environment, git: git).prepare!
  end

  def self.cleanup_for(preview_environment)
    path = preview_environment.workspace_path.presence || path_for(preview_environment).to_s
    FileUtils.rm_rf(path)
  rescue StandardError => e
    Rails.logger.warn("[PreviewWorkspace] cleanup failed for PreviewEnvironment ##{preview_environment.id}: #{e.class}: #{e.message}")
  end

  def initialize(preview_environment, git:)
    @preview_environment = preview_environment
    @job = preview_environment.job
    @repository = @job.repository
    @git = git
    @path = self.class.path_for(preview_environment)
    @env = { "GIT_TERMINAL_PROMPT" => "0" }
  end

  def prepare!
    raise "job has no branch to preview" if @job.branch_name.blank?

    FileUtils.rm_rf(@path)
    FileUtils.mkdir_p(@path.dirname)
    @git.run(
      "clone",
      "--branch", @job.branch_name,
      "--no-tags", authenticated_url, @path.to_s,
      env: @env
    )
    @git.run("remote", "set-url", "origin", @repository.remote_url, chdir: @path.to_s)
    @git.configure_author(BotIdentity.for(@job), chdir: @path.to_s)
    @preview_environment.update_columns(workspace_path: @path.to_s, updated_at: Time.current)
    @path.to_s
  rescue StandardError
    FileUtils.rm_rf(@path)
    raise
  end

  private

  def authenticated_url
    @repository.authenticated_url(user: @job.user)
  end
end
