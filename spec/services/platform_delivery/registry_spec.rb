require "rails_helper"

RSpec.describe PlatformDelivery::Registry do
  describe ".for" do
    it "returns a WebAdapter for the 'web' platform" do
      expect(described_class.for("web")).to be_a(PlatformDelivery::WebAdapter)
    end

    it "returns a BaseAdapter for unknown platforms" do
      expect(described_class.for("unknown_platform")).to be_a(PlatformDelivery::BaseAdapter)
    end

    it "returns a BaseAdapter for nil platform" do
      expect(described_class.for(nil)).to be_a(PlatformDelivery::BaseAdapter)
    end
  end

  describe ".registered?" do
    it "is true for built-in adapters" do
      expect(described_class.registered?("web")).to be true
    end

    it "is false for unknown platforms" do
      expect(described_class.registered?("unknown_platform")).to be false
    end
  end

  describe ".register" do
    let(:custom_adapter_class) do
      Class.new(PlatformDelivery::BaseAdapter) do
        def deliver(message:, platform_identity:) = "custom"
      end
    end

    after do
      # Reset runtime adapters after each example so tests don't bleed
      described_class.instance_variable_set(:@runtime_adapters, {})
    end

    it "registers an adapter for a platform and returns it via .for" do
      described_class.register("test_platform", custom_adapter_class)
      expect(described_class.for("test_platform")).to be_a(custom_adapter_class)
      expect(described_class.registered?("test_platform")).to be true
    end

    it "registered adapters take precedence over ADAPTERS defaults" do
      custom = Class.new(PlatformDelivery::BaseAdapter)
      described_class.register("web", custom)
      expect(described_class.for("web")).to be_a(custom)
    end
  end

  describe PlatformDelivery::WebAdapter do
    it "delivers without raising" do
      adapter = described_class.new
      session = ChatSession.create!(user: Factories.user)
      message = ChatMessage.new(chat_session: session, role: "assistant", content: { "text" => "Hi" })
      identity = Factories.platform_identity

      expect { adapter.deliver(message: message, platform_identity: identity) }.not_to raise_error
    end

    it "returns nil (no-op since ActionCable handles web delivery)" do
      adapter = described_class.new
      result = adapter.deliver(message: double("msg"), platform_identity: double("identity"))
      expect(result).to be_nil
    end
  end

  describe PlatformDelivery::BaseAdapter do
    it "raises NotImplementedError on deliver" do
      adapter = described_class.new
      expect {
        adapter.deliver(message: double("msg"), platform_identity: double("identity"))
      }.to raise_error(NotImplementedError)
    end
  end
end
