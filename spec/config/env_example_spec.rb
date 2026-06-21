require "rails_helper"

RSpec.describe ".env.example" do
  let(:env_example_path) { Rails.root.join(".env.example") }
  let(:env_example) { env_example_path.read }

  def env_names_from(path)
    text = Rails.root.join(path).read
    text.scan(/ENV(?:\[\s*["']([^"']+)["']\s*\]|\.fetch\(\s*["']([^"']+)["']|\.key\?\(\s*["']([^"']+)["']|\.include\?\(\s*["']([^"']+)["'])/)
      .flatten
      .compact
      .concat(text.scan(/env_boolean\.call\(\s*["']([^"']+)["']/).flatten)
  end

  it "documents every env var referenced by the required config surfaces" do
    documented = env_example.scan(/^([A-Z][A-Z0-9_]*)=/).flatten
    required = %w[
      RAILS_MASTER_KEY
      SOLID_QUEUE_IN_PUMA
      SYRUS_GITHUB_REPO
      SYRUS_BUG_REPORT_OWNER
    ]

    required.concat(env_names_from("config/environments/development.rb"))
    required.concat(env_names_from("config/environments/production.rb"))
    required.concat(env_names_from("config/environments/test.rb"))
    required.concat(env_names_from("config/database.yml"))
    required.concat(env_names_from("config/storage.yml"))
    required.concat(env_names_from("config/deploy.yml"))

    expect(documented).to include(*required.uniq.sort)
  end

  it "keeps a short inline comment on each assignment" do
    assignments = env_example.lines.grep(/\A[A-Z][A-Z0-9_]*=/)

    expect(assignments).not_to be_empty
    expect(assignments).to all(match(/\s#\s\S/))
  end

  # SYRUS_* env vars read via a bare ENV.fetch("X") (no positional or block
  # default) anywhere the production web/worker hits at runtime. With no default,
  # an unset value raises KeyError and 500s the process — so each MUST be carried
  # by the env files. This is the class of bug that hid SYRUS_GITHUB_REPO until a
  # real GIT_SHA made the build-revision link try to render.
  def directly_fetched_runtime_vars
    paths = Dir[Rails.root.join("app/**/*.rb")] +
            Dir[Rails.root.join("config/initializers/**/*.rb")] +
            [ Rails.root.join("config/environments/production.rb").to_s ]
    paths.flat_map do |path|
      vars = []
      File.read(path).scan(/ENV\.fetch\(\s*["'](SYRUS_[A-Z0-9_]+)["']\s*\)(\s*(?:\{|\bdo\b))?/) do |name, block|
        vars << name if block.to_s.strip.empty? # a trailing block is a default
      end
      vars
    end.uniq.sort
  end

  it "documents every directly-fetched SYRUS_* runtime var in .env.example" do
    documented = env_example.scan(/^([A-Z][A-Z0-9_]*)=/).flatten
    expect(documented).to include(*directly_fetched_runtime_vars)
  end

  describe "compose.env.example (single-host runtime template)" do
    let(:compose_keys) do
      Rails.root.join("compose.env.example").read.scan(/^([A-Z][A-Z0-9_]*)=/).flatten
    end

    it "sets the secrets and core runtime vars the container boots with" do
      expect(compose_keys).to include(
        "SECRET_KEY_BASE",
        "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
        "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
        "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT",
        "SYRUS_SQLITE",
        "SYRUS_APP_HOST",
        "SYRUS_GITHUB_REPO",
        "SYRUS_BUG_REPORT_OWNER"
      )
    end

    it "provides a value for every directly-fetched SYRUS_* runtime var" do
      # The container's .env is generated from this file, so a bare ENV.fetch in
      # runtime code must resolve here or the web/worker 500s on a fresh install.
      fetched = directly_fetched_runtime_vars
      expect(fetched).not_to be_empty # sanity: the scanner actually found fetches
      expect(compose_keys).to include(*fetched)
    end
  end
end
