require "rails_helper"

RSpec.describe HealthCheckJob do
  it "logs the message it receives" do
    allow(Rails.logger).to receive(:info)
    described_class.perform_now("M0 smoke test")
    expect(Rails.logger).to have_received(:info).with(/M0 smoke test/)
  end
end
