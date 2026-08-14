module SyrusRails
  class PreviewProvider
    def detect?(repo_path)
      File.exist?(File.join(repo_path, "Gemfile")) &&
        File.exist?(File.join(repo_path, "config", "application.rb")) &&
        File.exist?(File.join(repo_path, "bin", "rails"))
    end

    def start_command(port:)
      "bin/rails server -p #{port} -b 0.0.0.0 -e development"
    end

    def seed_command
      "bin/rails db:create db:migrate db:seed"
    end

    def setup_commands
      [
        "bundle config set --local path vendor/bundle",
        "bundle install --jobs 4"
      ]
    end

    def health_check_path
      "/up"
    end

    def log_paths
      ["log/development.log"]
    end

    def env
      {
        "RAILS_ENV" => "development",
        "SEARCH_DATABASE_PATH" => "storage/preview_search.sqlite3",
        "VITE_RUBY_SKIP_PROXY" => "false"
      }
    end

    def unset_env
      %w[
        DATABASE_URL
        CACHE_DATABASE_URL
        QUEUE_DATABASE_URL
        CABLE_DATABASE_URL
        DB_HOST
        SYRUS_DATABASE_PASSWORD
        SYRUS_SQLITE
      ]
    end
  end
end
