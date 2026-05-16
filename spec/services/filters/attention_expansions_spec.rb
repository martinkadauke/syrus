require "rails_helper"

RSpec.describe Filters::Chips::Attention do
  describe ".expansion_for" do
    it "returns a single chip for simple presets" do
      expect(described_class.expansion_for("pinned")).to eq(
        "field" => "pinned_by_me", "op" => "is_true", "value" => nil
      )
    end

    it "returns an AND tree for conjunctive presets like `stale`" do
      stale = described_class.expansion_for("stale")
      expect(stale).to have_key("and")
      expect(stale["and"]).to include(
        hash_including("field" => "state", "op" => "is", "value" => "open"),
        hash_including(
          "field" => "updated_at",
          "op" => "more_than_ago",
          "value" => { "n" => 7, "unit" => "days" }
        )
      )
    end

    it "returns an OR tree for disjunctive presets like `blocked`" do
      blocked = described_class.expansion_for("blocked")
      expect(blocked).to have_key("or")
      expect(blocked["or"]).to include(
        hash_including("field" => "has_blocked_deps", "op" => "is_true"),
        hash_including("field" => "pr_mergeable", "op" => "is_false")
      )
    end

    # `inbox` depends on awaiting_operator (no chip primitive) — the
    # UI hides the Expand button for it, gated by this returning nil.
    it "returns nil for presets without a clean primitive mapping" do
      expect(described_class.expansion_for("inbox")).to be_nil
    end

    it "returns nil for unknown values" do
      expect(described_class.expansion_for("not_a_preset")).to be_nil
    end
  end

  describe ".expansions" do
    it "includes every defined expansion as parsed AST nodes" do
      expansions = described_class.expansions
      expect(expansions.keys).to match_array(%w[
        pinned in_progress awaiting_approval just_failed in_review
        stale blocked merged_this_week awaiting_epic needs_review
      ])
    end
  end

  describe "expansion round-trip through the AST" do
    it "every expansion parses cleanly into an Ast node" do
      described_class.expansions.each do |preset, expansion|
        # AND/OR/chip — all must be parseable. We wrap chips in an
        # AND so the parser sees the expected root shape.
        wrapped = expansion.key?("and") || expansion.key?("or") ? expansion : { "and" => [ expansion ] }
        expect { Filters::Ast.parse(wrapped) }.not_to raise_error, "preset #{preset} failed to parse"
      end
    end
  end
end
