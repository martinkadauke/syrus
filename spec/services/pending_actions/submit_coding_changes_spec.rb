require "rails_helper"

RSpec.describe PendingActions::SubmitCodingChanges do
  include ActiveJob::TestHelper

  let(:user) { Factories.user }
  let(:repository) { Factories.repository(user: user) }
  let(:chat_session) { ChatSession.create!(user: user, repository: repository) }

  def enable_coding_mode!
    feature = Feature.find_or_create_by!(slug: "coding_mode") do |record|
      record.category = "Labs"
      record.name = "Coding Mode"
    end
    feature.update!(enabled: true)
  end

  def pending_action(overrides = {})
    chat_session.pending_actions.create!({
      action: "submit_coding_changes",
      payload: {
        "repository_id" => repository.id,
        "branch" => "feature/my-work",
        "title" => "User Profile Page",
        "description" => "Add user profile page"
      },
      requested_by: "agent"
    }.merge(overrides))
  end

  before do
    enable_coding_mode!
    allow(CodingHandoffCapture).to receive(:capture!) do |chat_session:, repository:, user:, source_branch:, handoff_branch:|
      {
        "source_branch" => source_branch,
        "handoff_branch" => handoff_branch,
        "head_sha" => "abc123",
        "base_sha" => "def456",
        "default_branch" => repository.default_branch,
        "changed_files" => [ "app/frontend/App.tsx" ],
        "captured_at" => Time.current.iso8601,
        "chat_session_id" => chat_session.id
      }
    end
  end

  it "creates a direct Job linked to the chat session" do
    action = pending_action

    allow(StepDispatcher).to receive(:start_workflow)
    expect { action.confirm!(user: user) }.to change(Job, :count).by(1)

    job = Job.order(:created_at).last
    expect(job).to have_attributes(
      kind: "direct",
      issue_title: "User Profile Page",
      issue_body: "Add user profile page",
      linked_chat_id: chat_session.id,
      repository: repository
    )
    expect(job.branch_name).to match(%r{\Asyrus/chat-#{chat_session.id}-handoff-\d+\z})
  end

  it "dispatches a coding_handoff workflow and stores it as the result" do
    action = pending_action

    allow(StepDispatcher).to receive(:start_workflow)
    action.confirm!(user: user)

    expect(action.reload).to be_confirmed
    expect(action.result).to be_a(Workflow)
    expect(action.result.trigger_kind).to eq("coding_handoff")
  end

  it "transitions the new Job to implemented state (out of coding) after handoff" do
    action = pending_action

    allow(StepDispatcher).to receive(:start_workflow)
    action.confirm!(user: user)

    job = action.result.job
    expect(job.reload).to be_implemented
  end

  it "captures and stores an immutable handoff branch instead of reusing the mutable chat branch" do
    action = pending_action

    allow(StepDispatcher).to receive(:start_workflow)
    action.confirm!(user: user)

    expect(CodingHandoffCapture).to have_received(:capture!).with(
      chat_session: chat_session,
      repository: repository,
      user: user,
      source_branch: "feature/my-work",
      handoff_branch: action.result.job.branch_name
    )
    expect(action.result.job.branch_name).to match(%r{\Asyrus/chat-#{chat_session.id}-handoff-\d+\z})
    expect(action.result.artifact("coding_handoff")).to include(
      "source_branch" => "feature/my-work",
      "handoff_branch" => action.result.job.branch_name,
      "head_sha" => "abc123"
    )
  end

  it "seeds PR summary and empty test-plan artifacts from the handoff" do
    action = pending_action

    allow(StepDispatcher).to receive(:start_workflow)
    action.confirm!(user: user)

    workflow = action.result.reload
    expect(workflow.artifact("pr_title")).to eq("User Profile Page")
    expect(workflow.artifact("pr_body")).to include("Captured chat workspace commit `abc123`")
    expect(workflow.artifact("pr_body")).to include("- `app/frontend/App.tsx`")
    expect(workflow.artifact("test_plan")).to eq("steps" => [], "notes" => nil)
  end

  it "sets issue_title from the payload and does not enqueue GenerateJobTitleJob" do
    action = pending_action

    allow(StepDispatcher).to receive(:start_workflow)
    expect {
      action.confirm!(user: user)
    }.not_to have_enqueued_job(GenerateJobTitleJob)

    job = action.result.job
    expect(job.issue_title).to eq("User Profile Page")
    expect(job.title_pending).to be(false)
  end

  it "raises RecordNotFound when the repository belongs to another user" do
    other_user = Factories.user
    other_repo = Factories.repository(user: other_user)
    action = pending_action({ payload: { "repository_id" => other_repo.id, "branch" => "main", "title" => "stuff", "description" => "stuff" } })

    expect { action.confirm!(user: user) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "raises ArgumentError when coding mode is disabled during confirmation" do
    action = pending_action
    Feature.find_by(slug: "coding_mode")&.update!(enabled: false)

    expect { action.confirm!(user: user) }.to raise_error(ArgumentError, /could not start coding handoff/)
  end

  it "validates that repository_id is present in the payload" do
    action = chat_session.pending_actions.build(
      action: "submit_coding_changes",
      payload: { "branch" => "main", "title" => "stuff", "description" => "stuff" },
      requested_by: "agent"
    )

    expect(action).not_to be_valid
    expect(action.errors.to_a).to include(match(/repository_id/))
  end

  it "validates that branch is present in the payload" do
    action = chat_session.pending_actions.build(
      action: "submit_coding_changes",
      payload: { "repository_id" => repository.id, "title" => "stuff", "description" => "stuff" },
      requested_by: "agent"
    )

    expect(action).not_to be_valid
    expect(action.errors.to_a).to include(match(/branch/))
  end

  it "validates that title is present in the payload" do
    action = chat_session.pending_actions.build(
      action: "submit_coding_changes",
      payload: { "repository_id" => repository.id, "branch" => "main", "description" => "stuff" },
      requested_by: "agent"
    )

    expect(action).not_to be_valid
    expect(action.errors.to_a).to include(match(/title/))
  end

  it "validates that description is present in the payload" do
    action = chat_session.pending_actions.build(
      action: "submit_coding_changes",
      payload: { "repository_id" => repository.id, "branch" => "main", "title" => "stuff" },
      requested_by: "agent"
    )

    expect(action).not_to be_valid
    expect(action.errors.to_a).to include(match(/description/))
  end
end
