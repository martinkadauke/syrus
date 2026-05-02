require "rails_helper"

RSpec.describe SyrusMcp::SubmitSummaryTool do
  let(:run) { Factories.job.initial_run }

  def call(pr_title: "Add greeting helper", pr_body: "Adds a tiny greet helper.", summary: "Implemented greet.")
    described_class.call(
      pr_title: pr_title, pr_body: pr_body, summary: summary,
      server_context: { run: run }
    )
  end

  describe "happy path" do
    it "persists all three fields on the Run" do
      call(pr_title: "Add greet", pr_body: "Adds it.", summary: "Done.")
      expect(run.reload).to have_attributes(
        agent_pr_title: "Add greet",
        agent_pr_body:  "Adds it.",
        agent_summary:  "Done."
      )
    end

    it "strips leading/trailing whitespace from each field" do
      call(pr_title: "  Add greet  ", pr_body: "\nAdds it.\n", summary: " Done. ")
      expect(run.reload).to have_attributes(
        agent_pr_title: "Add greet",
        agent_pr_body:  "Adds it.",
        agent_summary:  "Done."
      )
    end

    it "writes a JobLog audit line so the operator sees the call in the transcript" do
      expect { call(pr_title: "Add greet") }.to change { run.job_logs.count }.by(1)
      expect(run.job_logs.last.chunk).to include("[mcp] submit_summary received")
      expect(run.job_logs.last.chunk).to include("Add greet")
    end

    it "returns a non-error MCP::Tool::Response" do
      response = call
      expect(response).to be_a(MCP::Tool::Response)
      expect(response).not_to be_error
      expect(response.content.first[:text]).to eq("Saved.")
    end
  end

  describe "validation" do
    it "rejects empty pr_title" do
      response = call(pr_title: "   ")
      expect(response).to be_error
      expect(response.content.first[:text]).to match(/pr_title is required/)
      expect(run.reload.agent_pr_title).to be_nil
    end

    it "rejects pr_title over 120 chars" do
      response = call(pr_title: "A" * 121)
      expect(response).to be_error
      expect(response.content.first[:text]).to match(/pr_title too long/)
    end

    it "rejects empty pr_body" do
      response = call(pr_body: "")
      expect(response).to be_error
      expect(response.content.first[:text]).to match(/pr_body is required/)
    end

    it "rejects empty summary" do
      response = call(summary: "")
      expect(response).to be_error
      expect(response.content.first[:text]).to match(/summary is required/)
    end

    it "leaves the Run unchanged on a validation failure" do
      run.update!(agent_pr_title: "old", agent_pr_body: "old", agent_summary: "old")
      call(pr_title: "")
      expect(run.reload).to have_attributes(
        agent_pr_title: "old", agent_pr_body: "old", agent_summary: "old"
      )
    end
  end

  describe "schema surface" do
    it "exposes the tool name as `submit_summary` so claude lists it as mcp__syrus__submit_summary" do
      expect(described_class.tool_name).to eq("submit_summary")
    end

    it "marks all three fields as required" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to match_array(%w[pr_title pr_body summary])
    end
  end
end
