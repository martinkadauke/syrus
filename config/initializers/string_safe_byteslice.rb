class String
  def safe_byteslice(start, length = nil)
    fragment = if length.nil?
      byteslice(start)
    else
      byteslice(start, length)
    end

    fragment.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
  end
end
