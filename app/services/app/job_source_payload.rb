module App
  class JobSourcePayload
    include Rails.application.routes.url_helpers

    LANGUAGE_BY_EXTENSION = {
      "rb" => "ruby",
      "rake" => "ruby",
      "gemspec" => "ruby",
      "js" => "javascript",
      "mjs" => "javascript",
      "cjs" => "javascript",
      "ts" => "typescript",
      "jsx" => "javascript",
      "tsx" => "typescript",
      "py" => "python",
      "erb" => "erb",
      "html" => "html",
      "htm" => "html",
      "css" => "css",
      "scss" => "scss",
      "sass" => "sass",
      "json" => "json",
      "yml" => "yaml",
      "yaml" => "yaml",
      "md" => "markdown",
      "sh" => "shell",
      "bash" => "shell",
      "zsh" => "shell",
      "go" => "go",
      "java" => "java",
      "rs" => "rust",
      "php" => "php",
      "sql" => "sql",
      "xml" => "xml",
      "svg" => "xml",
      "toml" => "toml",
      "tf" => "hcl"
    }.freeze

    def self.build(job:, user:, params: {})
      new(job: job, user: user, params: params).payload
    end

    def initialize(job:, user:, params:)
      @job = job
      @user = user
      @params = params
      @repository = job.repository
    end

    def payload
      return unavailable_payload unless source_available?

      github = GithubClient.for(repository: @repository, user: @user)
      branch_commits = []
      merge_base_sha = nil

      if @job.branch_name.present?
        compare = github.compare_commits(@repository.slug, @repository.default_branch, @job.branch_name)
        branch_commits = Array(compare[:commits])
        merge_base_sha = compare[:merge_base_sha]
      end

      selected_ref = @params[:ref].presence || branch_commits.first&.fetch(:sha) || merge_base_sha || @repository.default_branch
      tree_result = load_tree(github, selected_ref)
      selected_path = @params[:path].presence

      base_payload(selected_ref: selected_ref, selected_path: selected_path, branch_commits: branch_commits, merge_base_sha: merge_base_sha)
        .merge(tree_result)
        .merge(file_result(github, selected_path, selected_ref, tree_result[:source_error]))
    rescue => e
      base_payload(selected_ref: @params[:ref].presence || @repository.default_branch, selected_path: @params[:path].presence)
        .merge(tree_items: [], tree_truncated: false, file: nil, source_error: e.message, file_error: nil)
    end

    private

    def source_available?
      @repository.installation&.active? || @user.github_token.present?
    end

    def unavailable_payload
      base_payload(selected_ref: @params[:ref].presence || @repository.default_branch, selected_path: @params[:path].presence)
        .merge(
          tree_items: [],
          tree_truncated: false,
          file: nil,
          source_error: "GitHub token not configured. Add one in Settings to browse source.",
          file_error: nil
        )
    end

    def load_tree(github, selected_ref)
      result = github.file_tree_at(@repository.slug, selected_ref)
      {
        tree_items: Array(result[:items]).map { |item| tree_item_json(item) },
        tree_truncated: result[:truncated] == true,
        source_error: nil
      }
    rescue => e
      {
        tree_items: [],
        tree_truncated: false,
        source_error: "Could not load file tree: #{e.message}"
      }
    end

    def file_result(github, selected_path, selected_ref, source_error)
      return { file: nil, file_error: nil } if selected_path.blank? || source_error.present?

      file = github.file_content_at(@repository.slug, selected_path, selected_ref)
      return { file: nil, file_error: "File not found." } unless file

      {
        file: {
          path: selected_path,
          name: File.basename(selected_path),
          size: file[:size].to_i,
          language: language_for(selected_path),
          content: file[:content].to_s
        },
        file_error: nil
      }
    rescue => e
      { file: nil, file_error: e.message }
    end

    def base_payload(selected_ref:, selected_path:, branch_commits: [], merge_base_sha: nil)
      {
        job_id: @job.id,
        repository: {
          id: @repository.id,
          slug: @repository.slug,
          default_branch: @repository.default_branch,
          repository_path: repository_path(@repository)
        },
        branch_name: @job.branch_name,
        default_ref: @repository.default_branch,
        selected_ref: selected_ref,
        selected_path: selected_path,
        merge_base_sha: merge_base_sha,
        branch_commits: branch_commits.map { |commit| commit_json(commit) },
        paths: {
          job_path: job_path(@job),
          source_path: source_job_path(@job),
          app_source_path: "/api/v1/app/jobs/#{@job.id}/source"
        }
      }
    end

    def tree_item_json(item)
      path = item[:path].to_s
      {
        path: path,
        name: File.basename(path),
        size: item[:size].to_i,
        language: language_for(path)
      }
    end

    def commit_json(commit)
      {
        sha: commit[:sha],
        short_sha: commit[:short_sha].presence || commit[:sha].to_s.first(7),
        message: commit[:message].to_s,
        date: iso8601(commit[:date])
      }
    end

    def language_for(path)
      LANGUAGE_BY_EXTENSION.fetch(File.extname(path.to_s).downcase.delete_prefix("."), "plaintext")
    end

    def iso8601(value)
      value.respond_to?(:iso8601) ? value.iso8601 : value&.to_s
    end
  end
end
