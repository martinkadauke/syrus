require "uri"

class IssueImageExtractor
  MAX_LINE_BYTES = 32.kilobytes
  MAX_URL_BYTES = 4.kilobytes

  def self.urls(markdown)
    new(markdown).urls
  end

  def initialize(markdown)
    @markdown = markdown.to_s
  end

  def urls
    @markdown.each_line.flat_map { |line| urls_from_line(line) }.uniq
  end

  private

  def urls_from_line(line)
    line = line.to_s.safe_byteslice(0, MAX_LINE_BYTES)
    urls = []
    offset = 0

    while (start = line.index("![", offset))
      alt_end = line.index("]", start + 2)
      break unless alt_end

      open = line.index("(", alt_end + 1)
      break unless open

      close = line.index(")", open + 1)
      break unless close

      raw_target = line[(open + 1)...close].to_s.strip
      raw_target = raw_target[1...-1] if raw_target.start_with?("<") && raw_target.end_with?(">")
      raw_target = raw_target.split(/[[:space:]]+/, 2).first.to_s
      normalized = normalize(raw_target.safe_byteslice(0, MAX_URL_BYTES))
      urls << normalized if normalized
      offset = close + 1
    end

    urls
  end

  def normalize(raw_url)
    url = raw_url.to_s.strip
    url = url[1...-1] if url.start_with?("<") && url.end_with?(">")
    uri = URI.parse(url)
    return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
end
