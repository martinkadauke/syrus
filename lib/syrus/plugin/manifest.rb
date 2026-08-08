module Syrus
  module Plugin
    # Immutable record holding one plugin's registration details.
    # Returned by PluginRegistry.all_plugins; `enabled` reflects current DB state.
    Manifest = Data.define(
      :name,
      :version,
      :provides,
      :metadata,
      :description,
      :homepage,
      :icon_url,
      :enabled,
      :default_enabled,
      :disableable,
      :category
    ) do
      def initialize(description: nil, homepage: nil, icon_url: nil, enabled: true, default_enabled: true, disableable: true, category: nil, **) = super

      def enabled? = enabled
      def default_enabled? = default_enabled
      def disableable? = disableable
    end
  end
end
