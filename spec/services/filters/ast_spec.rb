require "rails_helper"

RSpec.describe Filters::Ast do
  describe ".parse" do
    it "returns EMPTY for nil and {}" do
      expect(described_class.parse(nil)).to eq(described_class::EMPTY)
      expect(described_class.parse({})).to eq(described_class::EMPTY)
    end

    it "parses an AND root with chip children" do
      ast = described_class.parse("and" => [
        { "field" => "state", "op" => "is", "value" => "open" }
      ])

      expect(ast).to be_a(described_class::AndNode)
      expect(ast.children.size).to eq(1)
      expect(ast.children.first).to be_a(described_class::Chip)
      expect(ast.children.first.field).to eq("state")
      expect(ast.children.first.op).to eq("is")
      expect(ast.children.first.value).to eq("open")
    end

    it "parses an OR group nested under AND" do
      ast = described_class.parse("and" => [
        { "or" => [
          { "field" => "state", "op" => "is", "value" => "open" },
          { "field" => "state", "op" => "is", "value" => "closed" }
        ] }
      ])

      group = ast.children.first
      expect(group).to be_a(described_class::OrNode)
      expect(group.children.map(&:value)).to eq([ "open", "closed" ])
    end

    it "parses NOT wrappers around chips" do
      ast = described_class.parse("not" => { "field" => "state", "op" => "is", "value" => "open" })

      expect(ast).to be_a(described_class::NotNode)
      expect(ast.child).to be_a(described_class::Chip)
    end

    it "parses NOT wrappers around OR groups" do
      ast = described_class.parse("not" => { "or" => [
        { "field" => "state", "op" => "is", "value" => "open" }
      ] })

      expect(ast).to be_a(described_class::NotNode)
      expect(ast.child).to be_a(described_class::OrNode)
    end

    it "accepts symbol keys" do
      ast = described_class.parse(and: [{ field: "state", op: "is", value: "open" }])

      expect(ast.children.first.field).to eq("state")
    end

    it "defaults op to 'is' when omitted" do
      ast = described_class.parse("field" => "state", "value" => "open")

      expect(ast.op).to eq("is")
    end

    it "is idempotent on already-parsed AST nodes" do
      ast = described_class.parse("field" => "state", "op" => "is", "value" => "open")

      expect(described_class.parse(ast)).to equal(ast)
    end

    it "raises on unrecognized nodes" do
      expect { described_class.parse("nonsense" => true) }.to raise_error(ArgumentError)
    end

    it "raises when a non-Hash sneaks in" do
      expect { described_class.parse("not a hash") }.to raise_error(ArgumentError)
    end
  end

  describe ".serialize" do
    it "round-trips a complex tree" do
      raw = {
        "and" => [
          { "field" => "state", "op" => "is", "value" => "open" },
          { "or" => [
            { "field" => "tags", "op" => "contains_any", "value" => [ 1, 2 ] },
            { "field" => "attention", "op" => "is", "value" => "stale" }
          ] },
          { "not" => { "field" => "repository_id", "op" => "is", "value" => 99 } }
        ]
      }

      expect(described_class.serialize(described_class.parse(raw))).to eq(raw)
    end

    it "omits the value key for predicate ops (nil value)" do
      chip = described_class::Chip.new(field: "has_unread_feedback", op: "is_true", value: nil)

      expect(described_class.serialize(chip)).to eq("field" => "has_unread_feedback", "op" => "is_true")
    end
  end
end
