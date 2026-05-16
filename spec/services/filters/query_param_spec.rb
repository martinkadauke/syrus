require "rails_helper"

RSpec.describe Filters::QueryParam do
  describe ".encode + .decode round-trip" do
    it "preserves an AND-of-chips tree" do
      tree = {
        "and" => [
          { "field" => "state", "op" => "is", "value" => "open" },
          { "field" => "tags",  "op" => "contains_any", "value" => [ 1, 2 ] }
        ]
      }

      encoded = described_class.encode(tree)
      expect(described_class.decode(encoded)).to eq(tree)
    end

    it "preserves OR-groups and NOT wrappers" do
      tree = {
        "and" => [
          { "or" => [
            { "field" => "attention", "op" => "is", "value" => "inbox" },
            { "field" => "latest_run_state", "op" => "is", "value" => "failed" }
          ] },
          { "not" => { "field" => "tags", "op" => "contains_any", "value" => [ 99 ] } }
        ]
      }

      expect(described_class.decode(described_class.encode(tree))).to eq(tree)
    end

    it "produces URL-safe output (no +, /, or = padding)" do
      tree = { "field" => "title", "op" => "contains", "value" => "hello world?/+&=" }

      encoded = described_class.encode(tree)
      expect(encoded).to match(/\A[A-Za-z0-9_-]+\z/)
    end
  end

  describe ".decode" do
    it "returns nil for blank input" do
      expect(described_class.decode(nil)).to be_nil
      expect(described_class.decode("")).to be_nil
    end

    it "returns nil for malformed base64" do
      expect(described_class.decode("not!valid!base64!")).to be_nil
    end

    it "returns nil for valid base64 of non-JSON content" do
      garbage = Base64.urlsafe_encode64("not-json", padding: false)
      expect(described_class.decode(garbage)).to be_nil
    end

    it "returns nil for a JSON value that isn't a Hash" do
      array_json = Base64.urlsafe_encode64("[1, 2, 3]", padding: false)
      expect(described_class.decode(array_json)).to be_nil
    end
  end
end
