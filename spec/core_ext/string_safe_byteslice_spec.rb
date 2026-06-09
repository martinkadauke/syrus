require "rails_helper"

RSpec.describe "String#safe_byteslice" do
  it "returns valid UTF-8 when truncation splits a multibyte character" do
    text = "#{"a" * 4}€tail"

    slice = text.safe_byteslice(0, 6)

    expect(slice).to be_valid_encoding
    expect(slice).to start_with("aaaa")
  end

  it "supports tail slices without returning invalid UTF-8" do
    text = "head€tail"

    slice = text.safe_byteslice(-6, 6)

    expect(slice).to be_valid_encoding
    expect(slice).to end_with("tail")
  end
end
