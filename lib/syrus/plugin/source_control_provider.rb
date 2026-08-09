module Syrus
  module Plugin
    # Interface for repository host / source-control providers.
    #
    # Input sources answer "where does new work come from?". Source-control
    # providers answer "which installed plugin owns git-host operations for this
    # repository?" so PR, branch, and merge operations can move behind a plugin
    # boundary incrementally.
    module SourceControlProvider
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def provider_key
          raise NotImplementedError, "#{name} must implement .provider_key"
        end

        def display_name
          raise NotImplementedError, "#{name} must implement .display_name"
        end

        def available_for?(_repository)
          raise NotImplementedError, "#{name} must implement .available_for?"
        end

        def client_for(repository:, user: nil)
          raise NotImplementedError, "#{name} must implement .client_for"
        end
      end
    end
  end
end
