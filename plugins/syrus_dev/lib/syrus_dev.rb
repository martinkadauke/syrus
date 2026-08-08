require "syrus_dev/version"

module SyrusDev
  def self.enabled?
    Syrus::PluginRegistry.providers_for(:admin_page).include?(AdminPages)
  end
end

require "syrus_dev/engine"
