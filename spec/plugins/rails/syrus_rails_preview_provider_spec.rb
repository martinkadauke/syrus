require "rails_helper"
require_relative "../../../plugins/rails/lib/syrus_rails"

RSpec.describe SyrusRails::PreviewProvider do
  subject(:provider) { described_class.new }

  it "includes Syrus::Plugin::PreviewProvider" do
    expect(provider).to be_a(Syrus::Plugin::PreviewProvider)
  end

  describe "#detect?" do
    it "returns true when all three marker files exist" do
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, "Gemfile"))
        FileUtils.mkdir_p(File.join(dir, "config"))
        FileUtils.touch(File.join(dir, "config", "application.rb"))
        FileUtils.mkdir_p(File.join(dir, "bin"))
        FileUtils.touch(File.join(dir, "bin", "rails"))

        expect(provider.detect?(dir)).to be true
      end
    end

    it "returns false when bin/rails is absent" do
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, "Gemfile"))
        FileUtils.mkdir_p(File.join(dir, "config"))
        FileUtils.touch(File.join(dir, "config", "application.rb"))

        expect(provider.detect?(dir)).to be false
      end
    end

    it "returns false when Gemfile is absent" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        FileUtils.touch(File.join(dir, "config", "application.rb"))
        FileUtils.mkdir_p(File.join(dir, "bin"))
        FileUtils.touch(File.join(dir, "bin", "rails"))

        expect(provider.detect?(dir)).to be false
      end
    end

    it "returns false when config/application.rb is absent" do
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, "Gemfile"))
        FileUtils.mkdir_p(File.join(dir, "bin"))
        FileUtils.touch(File.join(dir, "bin", "rails"))

        expect(provider.detect?(dir)).to be false
      end
    end

    it "returns false for an empty directory" do
      Dir.mktmpdir do |dir|
        expect(provider.detect?(dir)).to be false
      end
    end
  end

  describe "#start_command" do
    it "returns the rails server command with the given port" do
      expect(provider.start_command(port: 3001))
        .to eq("bin/rails server -p 3001 -b 0.0.0.0 -e development")
    end

    it "interpolates the port into the command" do
      expect(provider.start_command(port: 4567))
        .to eq("bin/rails server -p 4567 -b 0.0.0.0 -e development")
    end
  end

  describe "#seed_command" do
    it "returns the db setup command" do
      expect(provider.seed_command).to eq("bin/rails db:create db:migrate db:seed")
    end
  end

  describe "#setup_commands" do
    it "installs gems into the preview workspace before seed/start" do
      expect(provider.setup_commands).to eq([
        "bundle config set --local path vendor/bundle",
        "bundle install --jobs 4"
      ])
    end
  end

  describe "#health_check_path" do
    it "returns /up" do
      expect(provider.health_check_path).to eq("/up")
    end
  end

  describe "#log_paths" do
    it "returns the development log path" do
      expect(provider.log_paths).to eq(["log/development.log"])
    end
  end

  describe "#env" do
    it "runs Rails previews in development with an isolated search database" do
      expect(provider.env).to eq(
        "RAILS_ENV" => "development",
        "SEARCH_DATABASE_PATH" => "storage/preview_search.sqlite3",
        "VITE_RUBY_SKIP_PROXY" => "false"
      )
    end
  end

  describe "#unset_env" do
    it "strips inherited production database settings" do
      expect(provider.unset_env).to include(
        "DATABASE_URL",
        "CACHE_DATABASE_URL",
        "QUEUE_DATABASE_URL",
        "CABLE_DATABASE_URL",
        "DB_HOST",
        "SYRUS_DATABASE_PASSWORD",
        "SYRUS_SQLITE"
      )
    end
  end
end

RSpec.describe "SyrusRails plugin registration" do
  before { Syrus::PluginRegistry.reset! }
  after  { Syrus::PluginRegistry.reset! }

  describe "SyrusRails.register!" do
    it "registers a SyrusRails::PreviewProvider under :preview_provider" do
      SyrusRails.register!
      providers = Syrus::PluginRegistry.providers_for(:preview_provider)
      expect(providers.first).to be_a(SyrusRails::PreviewProvider)
    end

    it "allows detect? to be called via PluginRegistry.providers_for" do
      SyrusRails.register!

      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, "Gemfile"))
        FileUtils.mkdir_p(File.join(dir, "config"))
        FileUtils.touch(File.join(dir, "config", "application.rb"))
        FileUtils.mkdir_p(File.join(dir, "bin"))
        FileUtils.touch(File.join(dir, "bin", "rails"))

        provider = Syrus::PluginRegistry.providers_for(:preview_provider).first
        expect(provider.detect?(dir)).to be true
      end
    end

    it "returns false for a non-Rails directory via the registry" do
      SyrusRails.register!

      Dir.mktmpdir do |dir|
        provider = Syrus::PluginRegistry.providers_for(:preview_provider).first
        expect(provider.detect?(dir)).to be false
      end
    end
  end
end

RSpec.describe Syrus::PreviewProviderResolver do
  before { Syrus::PluginRegistry.reset! }
  after  { Syrus::PluginRegistry.reset! }

  describe ".for" do
    it "returns the matching provider for a Rails repo path" do
      SyrusRails.register!

      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, "Gemfile"))
        FileUtils.mkdir_p(File.join(dir, "config"))
        FileUtils.touch(File.join(dir, "config", "application.rb"))
        FileUtils.mkdir_p(File.join(dir, "bin"))
        FileUtils.touch(File.join(dir, "bin", "rails"))

        resolver = described_class.for(dir)
        expect(resolver).to be_a(SyrusRails::PreviewProvider)
      end
    end

    it "returns nil when no provider detects the repo" do
      SyrusRails.register!

      Dir.mktmpdir do |dir|
        expect(described_class.for(dir)).to be_nil
      end
    end

    it "returns nil when no providers are registered" do
      Dir.mktmpdir do |dir|
        expect(described_class.for(dir)).to be_nil
      end
    end
  end
end
