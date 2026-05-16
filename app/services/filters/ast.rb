module Filters
  # Tree-shape AST for the new composable filter system. Three logical
  # node types (And / Or / Not) plus the leaf Chip. JSON serialization
  # uses three top-level keys — "and", "or", "not" — and chips render
  # as { "field", "op", "value" }. The AndNode-at-root constraint is
  # convention, not enforced; arbitrary nesting is technically allowed
  # but the UI emits DNF (AND-of-chips-or-OR-groups, with NOT wrapping
  # chips or groups).
  module Ast
    AndNode = Data.define(:children)
    OrNode  = Data.define(:children)
    NotNode = Data.define(:child)
    Chip    = Data.define(:field, :op, :value)

    EMPTY = AndNode.new(children: []).freeze

    # JSON-friendly tree → AST. Idempotent on AST input. nil and empty
    # hash both yield EMPTY (treated as "no filter applied").
    def self.parse(raw)
      return EMPTY if raw.nil? || raw == {}
      return raw if raw.is_a?(AndNode) || raw.is_a?(OrNode) || raw.is_a?(NotNode) || raw.is_a?(Chip)

      raise ArgumentError, "filter root must be a Hash, got #{raw.class}" unless raw.is_a?(Hash)

      build(raw.transform_keys(&:to_s))
    end

    # AST → JSON-friendly Hash with string keys only. The output is
    # safe to store on SmartFolder#filter and to embed in a URL via
    # base64.
    def self.serialize(node)
      case node
      when AndNode then { "and" => node.children.map { |c| serialize(c) } }
      when OrNode  then { "or"  => node.children.map { |c| serialize(c) } }
      when NotNode then { "not" => serialize(node.child) }
      when Chip
        h = { "field" => node.field, "op" => node.op }
        h["value"] = node.value unless node.value.nil?
        h
      else
        raise ArgumentError, "cannot serialize #{node.class}"
      end
    end

    def self.build(hash)
      if hash["and"].is_a?(Array)
        AndNode.new(children: hash["and"].map { |c| build_hash(c) })
      elsif hash["or"].is_a?(Array)
        OrNode.new(children: hash["or"].map { |c| build_hash(c) })
      elsif hash["not"]
        NotNode.new(child: build_hash(hash["not"]))
      elsif hash["field"]
        Chip.new(
          field: hash["field"].to_s,
          op: (hash["op"] || "is").to_s,
          value: hash["value"]
        )
      else
        raise ArgumentError, "unrecognized filter node: #{hash.inspect}"
      end
    end
    private_class_method :build

    def self.build_hash(raw)
      raise ArgumentError, "filter node must be a Hash, got #{raw.class}" unless raw.is_a?(Hash)

      build(raw.transform_keys(&:to_s))
    end
    private_class_method :build_hash
  end
end
