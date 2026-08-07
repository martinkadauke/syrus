module Syrus
  module Plugin
    # Interface for `:preview_provider` extension points. Plugin gems implement
    # this interface to tell Syrus how to start, seed, and health-check a preview
    # app for a given repository.
    #
    # Usage:
    #   class MyPlugin::PreviewProvider
    #     include Syrus::Plugin::PreviewProvider
    #
    #     def detect?(repo_path) = File.exist?(File.join(repo_path, "Gemfile"))
    #     def start_command(port:) = "bin/rails server -p #{port}"
    #     def seed_command = "bin/rails db:seed"
    #     def health_check_path = "/"
    #     def log_paths = ["log/development.log"]
    #   end
    #
    #   Syrus::PluginRegistry.register(
    #     name: "my-preview-plugin", version: "1.0.0",
    #     provides: { preview_provider: MyPlugin::PreviewProvider }
    #   )
    module PreviewProvider
      def self.register(provider)
        registry << provider
      end

      def self.registry
        @registry ||= []
      end

      def self.for_repo(repo_path)
        provider_candidates.find { |p| p.detect?(repo_path) }
      end

      def self.configured?
        registry.any? || Syrus::PluginRegistry.providers_for(:preview_provider).any?
      end

      def self.provider_candidates
        registry + Syrus::PluginRegistry.providers_for(:preview_provider).filter_map { |provider| instantiate(provider) }
      end

      def self.instantiate(provider)
        return provider if provider.respond_to?(:detect?)
        return provider.new if provider.respond_to?(:new)

        nil
      end

      # -- Interface methods providers must implement --

      def detect?(_repo_path)
        raise NotImplementedError, "#{self.class}#detect? is required"
      end

      def start_command(port:)
        raise NotImplementedError, "#{self.class}#start_command is required"
      end

      def seed_command
        nil
      end

      def health_check_path
        "/"
      end

      def log_paths
        []
      end
    end
  end
end
