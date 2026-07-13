require "rails_helper"

RSpec.describe SyrusChatMcp::CompleteImplementStepTool do
  let(:user) { Factories.user }
  let(:repository) { Factories.repository(user: user) }
  let(:chat_session) { ChatSession.create!(user: user, repository: repository, mode: "coding") }

  before { allow(StepDispatcher).to receive(:start_workflow) }

  def server
    MCP::Server.new(
      name: "syrus-chat-sidecar",
      tools: [ described_class ],
      server_context: { chat_session: chat_session }
    )
  end

  def call_tool(**arguments)
    raw = server.handle_json({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: "complete_implement_step", arguments: arguments }
    }.to_json)
    JSON.parse(raw, symbolize_names: true)
  end

  def payload(response)
    JSON.parse(response.dig(:result, :content, 0, :text), symbolize_names: true)
  end

  it "exits local mode and enqueues a handoff workflow for a job with a PR" do
    job = Factories.job_record(repository: repository, state: "implemented", branch_name: "syrus/job-1", pr_number: 10)
    job.update_columns(linked_chat_id: chat_session.id, state: "coding")

    response = call_tool(job_id: job.id)
    result = payload(response)

    expect(response.dig(:result, :isError)).to be_falsey
    expect(result[:job_id]).to eq(job.id)
    expect(job.reload.linked_chat_id).to be_nil
    expect(StepDispatcher).to have_received(:start_workflow)
  end

  it "rejects an unknown job_id" do
    response = call_tool(job_id: 999_999_999)

    expect(response.dig(:result, :isError)).to be(true)
    expect(response.dig(:result, :content, 0, :text)).to include("not found")
  end

  it "rejects a job not in coding state" do
    job = Factories.job_record(repository: repository, state: "implemented")

    response = call_tool(job_id: job.id)

    expect(response.dig(:result, :isError)).to be(true)
    expect(response.dig(:result, :content, 0, :text)).to include("not in coding state")
  end

  it "rejects a job linked to a different chat session" do
    other_chat = ChatSession.create!(user: user, mode: "coding")
    job = Factories.job_record(repository: repository, state: "implemented", pr_number: 5)
    job.update_columns(linked_chat_id: other_chat.id, state: "coding")

    response = call_tool(job_id: job.id)

    expect(response.dig(:result, :isError)).to be(true)
    expect(response.dig(:result, :content, 0, :text)).to include("not linked to this chat session")
  end

  it "requires branch_name for new jobs without a PR" do
    job = Factories.job_record(repository: repository, state: "running", kind: "direct", issue_number: nil)
    job.update_columns(linked_chat_id: chat_session.id, state: "coding", pr_number: nil, branch_name: nil)

    response = call_tool(job_id: job.id)

    expect(response.dig(:result, :isError)).to be(true)
    expect(response.dig(:result, :content, 0, :text)).to include("branch_name is required")
  end
end
