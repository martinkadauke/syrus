require "rails_helper"

RSpec.describe Prompts::EpicContext do
  let(:epic) do
    instance_double(
      Epic,
      slug: "EPIC-70",
      title: "Syrus CLI and test planning",
      description: "Build the Go CLI and the Rails-side test planning step."
    )
  end

  it "renders the Epic title, description, and scope guard" do
    out = described_class.new(epic: epic).to_s

    expect(out).to include("EPIC-70: Syrus CLI and test planning")
    expect(out).to include("Build the Go CLI and the Rails-side test planning step.")
    expect(out).to include("Do not implement the entire Epic")
    expect(out).to include("Implement only the Job described above")
  end

  it "renders the scope guard even when the Epic has no description" do
    allow(epic).to receive(:description).and_return(nil)

    out = described_class.new(epic: epic).to_s

    expect(out).to include("EPIC-70: Syrus CLI and test planning")
    expect(out).to include("Do not implement sibling Jobs")
    expect(out).not_to include("Epic description:")
  end

  it "is blank without an Epic" do
    expect(described_class.new(epic: nil).to_s).to eq("")
  end

  it "truncates long descriptions without splitting UTF-8" do
    description = "#{'a' * Prompts::EpicContext::MAX_DESCRIPTION_BYTES}é"
    allow(epic).to receive(:description).and_return(description)

    out = described_class.new(epic: epic).to_s

    expect(out).to be_valid_encoding
    expect(out).to include("[Epic description truncated after #{Prompts::EpicContext::MAX_DESCRIPTION_BYTES} bytes.]")
  end
end
