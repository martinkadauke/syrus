require "rails_helper"

RSpec.describe SyrusVersion do
  def with_env(**vars)
    saved = vars.transform_values { |_| nil }
    saved.each_key { |key| saved[key] = ENV[key.to_s] }
    vars.each { |key, value| value.nil? ? ENV.delete(key.to_s) : ENV[key.to_s] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key.to_s) : ENV[key.to_s] = value }
  end

  describe ".sidecar_process?" do
    it "detects run and chat MCP sidecars" do
      with_env(SYRUS_MCP_SIDECAR: "1", SYRUS_CHAT_MCP_SIDECAR: nil) do
        expect(described_class.sidecar_process?).to be(true)
      end

      with_env(SYRUS_MCP_SIDECAR: nil, SYRUS_CHAT_MCP_SIDECAR: "1") do
        expect(described_class.sidecar_process?).to be(true)
      end
    end
  end

  describe ".server_process?" do
    before do
      production_env = ActiveSupport::StringInquirer.new("production")
      allow(Rails).to receive(:env).and_return(production_env)
    end

    it "tracks normal web and worker processes" do
      with_env(SYRUS_ROLE: "worker", SYRUS_MCP_SIDECAR: nil, SYRUS_CHAT_MCP_SIDECAR: nil) do
        expect(described_class.server_process?).to be(true)
      end
    end

    it "does not track MCP sidecars even when they inherit SYRUS_ROLE" do
      with_env(SYRUS_ROLE: "worker", SYRUS_MCP_SIDECAR: "1", SYRUS_CHAT_MCP_SIDECAR: nil) do
        expect(described_class.server_process?).to be(false)
      end
    end
  end
end
