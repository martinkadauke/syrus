module SyrusRails
  class PreviewProvider
    def detect?(repo_path)
      File.exist?(File.join(repo_path, "Gemfile")) &&
        File.exist?(File.join(repo_path, "config", "application.rb")) &&
        File.exist?(File.join(repo_path, "bin", "rails"))
    end

    def start_command(port:)
      [
        "mkdir -p log tmp/pids",
        "if [ -f package.json ]; then npm run dev > log/vite.log 2>&1 & fi",
        "exec bin/rails server -p #{port} -b 0.0.0.0 -e development"
      ].join(" && ")
    end

    def seed_command
      "bin/rails db:create db:migrate db:seed"
    end

    def setup_commands
      [
        "bundle config set --local path vendor/bundle",
        "bundle install --jobs 4",
        "if [ -f package-lock.json ]; then npm ci; elif [ -f pnpm-lock.yaml ]; then corepack enable && pnpm install --frozen-lockfile; elif [ -f yarn.lock ]; then corepack enable && yarn install --frozen-lockfile; elif [ -f bun.lockb ] || [ -f bun.lock ]; then bun install --frozen-lockfile; fi"
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
