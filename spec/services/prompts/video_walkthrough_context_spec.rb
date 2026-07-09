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
          "user_flagged" => true, "needs_closer_look" => true,
          "unreadable_text" => "the error code in the red toast, bottom-right"
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

  # The Save issue at 01:12 with title "Save button does nothing".
  def save_issue_key
    described_class.attachment_key(seconds: 72, title: "Save button does nothing")
  end

  it "renders an ATTACHED issue's unreadable_text as a read-off-the-attached-screenshot line" do
    text = described_class.new(
      walkthrough: walkthrough, illustrated: true, attached_issue_keys: [ save_issue_key ]
    ).to_s

    expect(text).to include("read the exact text off the attached screenshot: the error code in the red toast, bottom-right")
    expect(text).not_to include("no screenshot is attached")
  end

  it "renders an UNATTACHED flagged issue as a fetch-on-demand line, never claiming a screenshot" do
    # No attachments → the flagged issue has no screenshot; the agent is pointed
    # at the on-demand tool instead of being told to read a still that isn't there.
    text = described_class.new(walkthrough: walkthrough).to_s

    expect(text).to include("no screenshot is attached")
    expect(text).to include("read_walkthrough_frame(walkthrough_id: 7, timestamp: 01:12)")
    expect(text).not_to include("read the exact text off the attached screenshot")
  end

  it "adds the read-attached OCR handoff (read exact text, never invent) when the flagged issue's screenshot IS attached" do
    text = described_class.new(
      walkthrough: walkthrough, illustrated: true, attached_issue_keys: [ save_issue_key ]
    ).to_s

    expect(text).to include("## Read the exact text off the screenshots")
    expect(text).to match(/READ the precise text/)
    expect(text).to match(/NEVER invent/)
    # Points the agent at which screenshot / moment to read.
    expect(text).to include("at 01:12")
    expect(text).to include("the error code in the red toast, bottom-right")
  end

  it "omits the read-attached OCR handoff when nothing is attached (no screenshots)" do
    text = described_class.new(walkthrough: walkthrough, illustrated: false).to_s
    expect(text).not_to include("## Read the exact text off the screenshots")
  end

  it "on a text-only turn still carries the never-invent guard AND the read_walkthrough_frame fallback" do
    # No attachments: the anti-hallucination guard must NOT be gated on
    # illustrated, and the miss must degrade into an on-demand fetch.
    text = described_class.new(walkthrough: walkthrough, illustrated: false).to_s

    expect(text).to include("## Fetch and read these screenshots on demand")
    expect(text).to match(/NEVER invent/)
    expect(text).to include("read_walkthrough_frame(walkthrough_id: 7, timestamp: 01:12)")
    # ...and it must NOT tell the agent to read an attached screenshot.
    expect(text).not_to include("read the exact text off the attached screenshot")
  end

  it "lists only ATTACHED flagged issues under 'read' and the rest under fetch-on-demand" do
    issues = (1..3).map do |n|
      {
        "title" => "Issue #{n}", "severity" => "high", "timestamp" => format("00:%02d", n * 10),
        "description" => "d#{n}", "unreadable_text" => "value #{n}", "needs_closer_look" => true
      }
    end
    wt = walkthrough(analysis_issues: issues)
    # Only Issue 1 (at 00:10) actually got an attached frame.
    attached = [ described_class.attachment_key(seconds: 10, title: "Issue 1") ]

    text = described_class.new(walkthrough: wt, illustrated: true, attached_issue_keys: attached).to_s

    read_idx = text.index("## Read the exact text off the screenshots")
    fetch_idx = text.index("## Fetch and read these screenshots on demand")
    expect(read_idx).to be_present
    expect(fetch_idx).to be_present

    read_section = text[read_idx...fetch_idx]
    fetch_section = text[fetch_idx..]

    # Section A "read:" lists only the attached issue.
    expect(read_section).to include("value 1")
    expect(read_section).not_to include("value 2")
    expect(read_section).not_to include("value 3")

    # Section B lists the two that were NOT attached, each with a fetch call.
    expect(fetch_section).to include("value 2")
    expect(fetch_section).to include("value 3")
    expect(fetch_section).to include("read_walkthrough_frame")
  end

  it "omits the OCR handoff instruction when illustrated but no issue was flagged unreadable" do
    plain = walkthrough(
      analysis_issues: [ { "title" => "x", "severity" => "low", "description" => "y" } ]
    )
    text = described_class.new(walkthrough: plain, illustrated: true).to_s
    expect(text).not_to include("## Read the exact text off the screenshots")
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
