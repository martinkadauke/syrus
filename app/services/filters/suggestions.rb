module Filters
  class Suggestions
    LIMIT = 5

    def self.record!(user:, surface:, subject:, tree:)
      new(user:, surface:, subject:).record!(tree)
    end

    def self.for(user:, surface:, subject:, active_tree: nil, limit: LIMIT)
      new(user:, surface:, subject:).suggestions(active_tree:, limit:)
    end

    def initialize(user:, surface:, subject:)
      @user = user
      @surface = surface.to_s
      @subject = subject.to_s
      @schema = Filters::Schema.for(subject: @subject.to_sym, user: user)
    end

    def record!(tree)
      each_suggestible_node(tree) do |node|
        upsert_usage!(node)
      end
    end

    def suggestions(active_tree: nil, limit: LIMIT)
      active_fingerprints = each_suggestible_node(active_tree).map { |node| fingerprint(node) }

      FilterUsage
        .where(user: user, surface: surface, subject: subject)
        .order(Arel.sql("use_count DESC, last_used_at DESC, id DESC"))
        .limit(limit * 3)
        .filter_map { |usage| suggestion_json(usage, active_fingerprints) }
        .first(limit)
    end

    private

    attr_reader :user, :surface, :subject, :schema

    def upsert_usage!(node)
      label = node_label(node)
      now = Time.current
      usage = FilterUsage.find_or_initialize_by(
        user: user,
        surface: surface,
        subject: subject,
        fingerprint: fingerprint(node)
      )
      usage.filter_node = node
      usage.label = label
      usage.use_count = usage.use_count.to_i + 1
      usage.last_used_at = now
      usage.save!
    end

    def suggestion_json(usage, active_fingerprints)
      node = normalized_node(usage.filter_node)
      return nil unless node && known_node?(node)
      return nil if active_fingerprints.include?(fingerprint(node))

      {
        id: usage.id,
        label: node_label(node),
        filter: node,
        use_count: usage.use_count,
        last_used_at: usage.last_used_at&.iso8601
      }
    end

    def each_suggestible_node(tree)
      return enum_for(:each_suggestible_node, tree) unless block_given?

      nodes = top_level_nodes(tree)
      nodes.each do |node|
        normalized = normalized_node(node)
        yield normalized if normalized && known_node?(normalized) && recordable_node?(normalized)
      end
    end

    def top_level_nodes(tree)
      hash = normalize_hash(tree)
      return [] unless hash
      return hash.fetch("and").filter_map { |child| normalize_hash(child) } if hash["and"].is_a?(Array)

      [ hash ]
    end

    def normalized_node(node)
      Filters::Ast.serialize(Filters::Ast.parse(normalize_hash(node)))
    rescue ArgumentError
      nil
    end

    def known_node?(node)
      case node
      when Hash
        if node["field"]
          schema_by_field.key?(node.fetch("field").to_s)
        elsif node["or"].is_a?(Array)
          node.fetch("or").any? && node.fetch("or").all? { |child| known_node?(child) }
        elsif node["not"].is_a?(Hash)
          known_node?(node.fetch("not"))
        else
          false
        end
      else
        false
      end
    end

    def recordable_node?(node)
      if node["field"]
        predicate_op?(node.fetch("op", "is")) || present_filter_value?(node["value"])
      elsif node["or"].is_a?(Array)
        node.fetch("or").any? && node.fetch("or").all? { |child| recordable_node?(child) }
      elsif node["not"].is_a?(Hash)
        recordable_node?(node.fetch("not"))
      else
        false
      end
    end

    def present_filter_value?(value)
      case value
      when Array
        value.any? { |child| present_filter_value?(child) }
      when Hash
        value.any? { |_key, child| present_filter_value?(child) }
      else
        !value.nil? && value != ""
      end
    end

    def fingerprint(node)
      Digest::SHA256.hexdigest(canonical_json(node))
    end

    def canonical_json(value)
      JSON.generate(canonical_value(value))
    end

    def canonical_value(value)
      case value
      when Hash
        value.transform_keys(&:to_s).sort.to_h { |key, child| [ key, canonical_value(child) ] }
      when Array
        value.map { |child| canonical_value(child) }
      else
        value
      end
    end

    def node_label(node)
      if node["field"]
        chip_label(node)
      elsif node["or"].is_a?(Array)
        node.fetch("or").map { |child| node_label(child) }.join(" OR ")
      elsif node["not"].is_a?(Hash)
        "NOT #{node_label(node.fetch("not"))}"
      else
        "Filter"
      end
    end

    def chip_label(chip)
      meta = schema_by_field[chip.fetch("field").to_s]
      label = meta&.fetch("label", nil) || chip.fetch("field").to_s
      op = humanize_op(chip.fetch("op", "is"))
      return "#{label} #{op}" if predicate_op?(chip.fetch("op", "is"))

      "#{label} #{op} #{value_label(chip, meta)}"
    end

    def value_label(chip, meta)
      value = chip["value"]
      return "(unset)" if value.nil? || value == ""
      return value.map { |child| single_value_label(child, meta) }.join(", ") if value.is_a?(Array)
      return relative_time_value_label(chip, value) if relative_time_value?(value)
      return JSON.generate(value) if value.is_a?(Hash)

      single_value_label(value, meta)
    end

    def single_value_label(value, meta)
      return value.to_s unless meta

      option = options_for(meta).find { |candidate| candidate.fetch("value").to_s == value.to_s }
      return option.fetch("label") if option

      fk_label(value, meta) || value.to_s
    end

    def fk_label(value, meta)
      return nil unless meta["bucket"] == "fk" || meta["typeahead"]

      Filters::FkOptionsResolver
        .new(user: user)
        .resolve(field: meta.fetch("field"), ids: [ value ], limit: nil)
        .first&.fetch("label", nil)
    rescue Filters::FkOptionsResolver::UnknownField
      nil
    end

    def options_for(meta)
      Array(meta["values"]).map do |option|
        option.is_a?(Hash) ? option.transform_keys(&:to_s) : { "value" => option, "label" => humanize_option(option) }
      end
    end

    def schema_by_field
      @schema_by_field ||= schema.to_h do |field|
        [ field.fetch("field").to_s, field.transform_keys(&:to_s) ]
      end
    end

    def normalize_hash(value)
      return nil unless value.is_a?(Hash)

      value.deep_stringify_keys
    end

    def predicate_op?(op)
      %w[is_set is_unset is_true is_false].include?(op.to_s)
    end

    def humanize_op(op)
      op.to_s.tr("_", " ")
    end

    def humanize_option(value)
      value.to_s.tr("_", " ").sub(/\A./, &:upcase)
    end

    def relative_time_value?(value)
      value.is_a?(Hash) && value.key?("n") && value.key?("unit")
    end

    def relative_time_value_label(chip, value)
      suffix = chip["op"] == "more_than_ago" ? " ago" : ""
      "#{value["n"]} #{value["unit"]}#{suffix}"
    end
  end
end
