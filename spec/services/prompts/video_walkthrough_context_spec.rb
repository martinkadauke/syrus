require "rails_helper"

RSpec.describe Prompts::VideoWalkthroughContext do
  def walkthrough(overrides = {})
    defaults = {
      id: 7,
      duration_seconds: 95,
      analysis_summary: "Tested checkout; Save fails silently.",
      analysis_sections: [
        { "start" => "00:00", "end" => "00:40", "title" => "Checkout", "summary" => "Adds items and pays." },
        { "start" => "00:40", "end" => "01:35", "title" => "Settings", "summary" => "Tries to save preferences." }
      ],
      analysis_issues: [
        {
          "title" => "Save button does nothing", "severity" => "high", "surface" => "settings",
          "timestamp" => "01:12", "description" => "Clicking Save shows no feedback.",
          "transcript_evidence" => "nothing happens when I hit save",
          "visual_evidence" => "the spinner never appears",
          "user_flagged" => true, "needs_closer_look" => true
        },
        {
          "title" => "Header contrast is low", "severity" => "low", "surface" => "header",
          "timestamp" => "00:20", "description" => "Gray on gray."
        }
      ],
      analysis_open_questions: [ "Should drafts autosave?" ],
      analysis_transcript: [
        { "timestamp" => "00:03", "text" => "Okay, adding a widget to the cart." },
        { "timestamp" => "01:12", "text" => "nothing happens when I hit save" }
      ]
    }
    double(**defaults.merge(overrides))
  end

  it "renders sections, issues with the new fields, and the transcript" do
    text = described_class.new(walkthrough: walkthrough).to_s

    expect(text).to include("## Sections")
    expect(text).to include("**Checkout** (00:00–00:40) — Adds items and pays.")

    expect(text).to include("## Issues found (2)")
    expect(text).to include("**Save button does nothing** (high, settings, at 01:12, user-flagged, needs a closer look)")
    expect(text).to include("The user said: \"nothing happens when I hit save\"")
    expect(text).to include("On screen: the spinner never appears")

    expect(text).to include("## Narration transcript")
    expect(text).to include("[00:03] Okay, adding a widget to the cart.")
  end

  it "orders issues high → medium → low" do
    text = described_class.new(walkthrough: walkthrough).to_s
    expect(text.index("Save button does nothing")).to be < text.index("Header contrast is low")
  end

  it "points the agent at analyze_walkthrough_segment for needs_closer_look issues" do
    text = described_class.new(walkthrough: walkthrough).to_s
    expect(text).to include("analyze_walkthrough_segment")
    expect(text).to include("walkthrough #7")
    expect(text).to include("needs a closer look")
  end

  it "omits the closer-look note when no issue needs one" do
    plain = walkthrough(
      analysis_issues: [ { "title" => "x", "severity" => "low", "description" => "y" } ]
    )
    text = described_class.new(walkthrough: plain).to_s
    expect(text).not_to include("analyze_walkthrough_segment")
  end

  it "still steers toward the Epic proposal flow and includes the note when given" do
    text = described_class.new(walkthrough: walkthrough, user_note: "watch Save", illustrated: true).to_s
    expect(text).to include("The user's note with the video: watch Save")
    expect(text).to include("attached a screenshot for each issue")
    expect(text).to include("propose an Epic")
  end
end
