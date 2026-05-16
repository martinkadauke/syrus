module Filters
  # Encode / decode an AST tree to a single URL-safe query param so
  # the chip-bar UI can round-trip the full filter (including OR
  # groups and NOT wrappers) through the URL without dragging dozens
  # of flat keys with it.
  #
  # Wire format: base64-url(JSON(tree)). Base64-URL (no padding)
  # keeps the URL friendly to copy-paste — no `+/=` characters that
  # have special meaning in URLs.
  #
  # We deliberately do NOT compress: typical filter trees are small
  # (<1KB), and skipping zlib means the encoded value is human-ish
  # inspectable with one decode step.
  module QueryParam
    PARAM_NAME = :q

    module_function

    def encode(tree)
      json = JSON.generate(tree)
      Base64.urlsafe_encode64(json, padding: false)
    end

    # nil-safe. Returns the parsed tree as a Hash, or nil if the
    # input is blank or malformed. Doesn't raise — the controller
    # treats a bad q= as "no filter" so a broken bookmark doesn't
    # 500 the dashboard.
    def decode(raw)
      return nil if raw.blank?

      json = Base64.urlsafe_decode64(raw.to_s)
      parsed = JSON.parse(json)
      parsed.is_a?(Hash) ? parsed : nil
    rescue ArgumentError, JSON::ParserError
      nil
    end
  end
end
