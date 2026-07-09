require "rails_helper"

RSpec.describe Prompts::VideoWalkthroughAnalysis do
  describe "RESPONSE_SCHEMA" do
    subject(:schema) { described_class::RESPONSE_SCHEMA }

    let(:properties) { schema[:properties] }

    it "leads with a timestamped transcript (Flash transcribes best; it anchors the rest)" do
      transcript = properties[:transcript]
      expect(transcript[:type]).to eq("array")
      expect(transcript.dig(:items, :properties).keys).to contain_exactly(:timestamp, :text)
      expect(transcript.dig(:items, :required)).to contain_exactly("timestamp", "text")
    end

    it "segments the session into re-analyzable ranges with start/end" do
      section = properties[:sections][:items]
      expect(section[:properties].keys).to contain_exactly(:start, :end, :title, :summary)
      expect(section[:required]).to contain_exactly("start", "end", "title", "summary")
    end

    it "grounds each issue in transcript + visual evidence and flags detail signals" do
      issue = properties[:issues][:items]
      expect(issue[:properties].keys).to include(
        :timestamp, :title, :description, :severity, :surface,
        :transcript_evidence, :visual_evidence, :user_flagged, :needs_closer_look
      )
      expect(issue.dig(:properties, :severity, :enum)).to eq(%w[low medium high])
      expect(issue.dig(:properties, :user_flagged, :type)).to eq("boolean")
      expect(issue.dig(:properties, :needs_closer_look, :type)).to eq("boolean")
      expect(issue[:required]).to contain_exactly("title", "description", "severity")
    end

    it "requires the transcript alongside summary/issues/open_questions and drops positive_notes" do
      expect(schema[:required]).to contain_exactly("transcript", "summary", "issues", "open_questions")
      expect(properties).not_to have_key(:positive_notes)
      expect(properties).to have_key(:summary)
      expect(properties).to have_key(:open_questions)
    end
  end

  describe "#to_s" do
    subject(:prompt) { described_class.new.to_s }

    it "orders the work transcribe-first, then sections, then issues" do
      transcribe = prompt.index("TRANSCRIBE")
      segment = prompt.index("SEGMENT")
      extract = prompt.index("EXTRACT")
      expect([ transcribe, segment, extract ]).to all(be_present)
      expect(transcribe).to be < segment
      expect(segment).to be < extract
    end

    it "names the audio narration as the primary signal" do
      expect(prompt).to match(/AUDIO NARRATION is\s+your primary signal/)
    end

    it "asks for the user's own words as transcript_evidence" do
      expect(prompt).to include("transcript_evidence")
      expect(prompt).to match(/OWN WORDS/)
    end

    it "treats red pen marks / verbal pointers as strong locators for user_flagged" do
      expect(prompt).to include("red pen")
      expect(prompt).to include("user_flagged")
      expect(prompt).to include('"here"')
      expect(prompt).to include('"look at this"')
    end

    it "explains needs_closer_look for small-text / fast-action moments" do
      expect(prompt).to include("needs_closer_look")
      expect(prompt).to match(/small\s+text or fast action/)
    end
  end
end

RSpec.describe Prompts::VideoWalkthroughSegment do
  describe "RESPONSE_SCHEMA" do
    it "is focused: findings required, plus exact_text / steps / transcript detail" do
      schema = described_class::RESPONSE_SCHEMA
      expect(schema[:properties].keys).to contain_exactly(:findings, :exact_text, :steps, :transcript)
      expect(schema[:required]).to eq(%w[findings])
    end
  end

  describe "#to_s" do
    it "focuses on the caller's ask and asks for verbatim on-screen text at full resolution" do
      prompt = described_class.new(focus: "the exact error text", clock_range: "1:12–1:48").to_s
      expect(prompt).to include("the exact error text")
      expect(prompt).to include("1:12–1:48")
      expect(prompt).to include("full resolution")
      expect(prompt).to match(/verbatim/)
    end

    it "falls back to a generic description when focus is blank" do
      expect(described_class.new(focus: "").to_s).to include("Describe exactly what happens")
    end
  end
end
