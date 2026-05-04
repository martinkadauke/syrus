require "rails_helper"

RSpec.describe AdminAction do
  let(:user) { Factories.user }

  describe ".log!" do
    it "creates an append-only audit row with action + JSON params + performed_at" do
      record = described_class.log!(user: user, action: :pause_polling, params: { reason: "deploy" })
      expect(record).to be_persisted
      expect(record.user).to eq(user)
      expect(record.action).to eq("pause_polling")
      expect(record.params).to eq("reason" => "deploy")
      expect(record.performed_at).to be_within(2.seconds).of(Time.current)
    end

    it "rejects updates" do
      record = described_class.log!(user: user, action: :foo)
      expect { record.update!(action: "bar") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "rejects direct destroys" do
      record = described_class.log!(user: user, action: :foo)
      expect { record.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe ".recent" do
    it "returns the latest 50 by performed_at desc" do
      old = described_class.log!(user: user, action: :a, params: {})
      old.update_columns(performed_at: 1.year.ago)  # bypass append-only guard via update_columns
      new = described_class.log!(user: user, action: :b, params: {})
      expect(described_class.recent.first).to eq(new)
    end
  end
end
