require "rails_helper"

RSpec.describe InstanceVersion do
  def fixture(**overrides)
    InstanceVersion.create!({
      hostname: "syrus-web-abc",
      role: "web",
      version: "1234567",
      started_at: 1.minute.ago,
      last_heartbeat_at: 5.seconds.ago
    }.merge(overrides))
  end

  describe "#stale?" do
    it "is false for a fresh heartbeat" do
      expect(fixture(last_heartbeat_at: 10.seconds.ago)).not_to be_stale
    end

    it "is true when heartbeat is older than the threshold" do
      expect(fixture(last_heartbeat_at: 5.minutes.ago)).to be_stale
    end

    it "is false for a just-registered instance with no heartbeat yet" do
      expect(fixture(last_heartbeat_at: nil, started_at: 5.seconds.ago)).not_to be_stale
    end

    it "is true for an instance that registered but never heartbeated and has aged past threshold" do
      expect(fixture(last_heartbeat_at: nil, started_at: 10.minutes.ago)).to be_stale
    end

    it "is false once finalized" do
      sp = fixture(finished_at: 1.minute.ago, outcome: "shutdown")
      expect(sp).not_to be_stale
    end
  end

  describe ".fresh" do
    it "returns running rows whose last_heartbeat_at is within the threshold" do
      fresh = fixture(last_heartbeat_at: 10.seconds.ago)
      fixture(hostname: "syrus-web-stale", last_heartbeat_at: 10.minutes.ago)
      fixture(hostname: "syrus-web-done", finished_at: 30.seconds.ago, outcome: "shutdown")

      expect(InstanceVersion.fresh).to contain_exactly(fresh)
    end

    it "treats a recently-created row with no heartbeat as fresh" do
      newly = fixture(last_heartbeat_at: nil, started_at: 5.seconds.ago)

      expect(InstanceVersion.fresh).to include(newly)
    end
  end

  describe "#seconds_since_heartbeat" do
    it "is nil when there's no heartbeat yet" do
      expect(fixture(last_heartbeat_at: nil).seconds_since_heartbeat).to be_nil
    end

    it "rounds to whole seconds" do
      sp = fixture(last_heartbeat_at: 7.4.seconds.ago)
      expect(sp.seconds_since_heartbeat).to be_between(6, 8)
    end
  end
end
