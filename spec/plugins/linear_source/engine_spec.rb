require "rails_helper"

RSpec.describe SyrusLinearSource::Engine do
  it "registers the Linear input source plugin disabled by default" do
    manifest = Syrus::PluginRegistry.all_plugins.find { |plugin| plugin.name == "syrus-linear-source" }

    expect(manifest).to be_present
    expect(manifest.default_enabled?).to be(false)
    expect(Syrus::PluginRegistry.providers_for(:input_source)).not_to include(InputSources::Linear)
  end

  it "exposes the Linear input source provider when enabled" do
    PluginRecord.find_by!(name: "syrus-linear-source").update!(enabled: true)

    expect(Syrus::PluginRegistry.providers_for(:input_source)).to include(InputSources::Linear)
  end
end
