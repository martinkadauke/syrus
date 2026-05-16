require "rails_helper"

RSpec.describe Filters::Schema do
  describe ".chip_for" do
    # Regression: class instance variables in Ruby do NOT inherit
    # through `<`. Before the fix, AgentProvider (EnumColumn subclass)
    # reported bucket="" and operators=[] — the chip-bar UI fell back
    # to free-text input instead of an enum dropdown.
    it "inherits bucket from a bucket base class (EnumColumn)" do
      schema = described_class.chip_for("agent_provider")
      expect(schema["bucket"]).to eq("enum")
      expect(schema["operators"]).to include("is", "is_one_of", "is_set")
      expect(schema["values"]).to eq(%w[claude codex])
    end

    it "inherits string operators from StringColumn base" do
      schema = described_class.chip_for("title")
      expect(schema["bucket"]).to eq("string")
      expect(schema["operators"]).to include(
        "contains", "does_not_contain",
        "starts_with", "ends_with",
        "equals", "is_set"
      )
    end

    it "inherits date operators from DateColumn base" do
      schema = described_class.chip_for("created_at")
      expect(schema["bucket"]).to eq("date")
      expect(schema["operators"]).to be_present
    end

    it "inherits number operators from NumberColumn base" do
      schema = described_class.chip_for("issue_number")
      expect(schema["bucket"]).to eq("number")
      expect(schema["operators"]).to be_present
    end

    it "still respects per-chip overrides for bucket and values" do
      schema = described_class.chip_for("priority")
      expect(schema["bucket"]).to eq("enum")
      expect(schema["values"]).to eq(%w[high medium low])
    end
  end
end
