require "rails_helper"

RSpec.describe VideoWalkthroughPruneJob do
  let(:user) { Factories.user }
  let(:chat) { ChatSession.create!(user: user) }

  # Build a walkthrough in the given state with an attached blob, then force
  # updated_at to `age.ago` without bumping it (update_columns skips
  # timestamps/validations so the prune window is under test control).
  def walkthrough_with_blob(state:, age:, analysis: { "summary" => "s" })
    walkthrough = ChatVideoWalkthrough.new(
      chat_session: chat,
      user: user,
      content_type: "video/webm",
      byte_size: 10,
      duration_seconds: 60,
      analysis: analysis
    )
    walkthrough.file.attach(io: StringIO.new("webm-bytes"), filename: "walkthrough.webm", content_type: "video/webm")
    walkthrough.save!
    # State + updated_at set directly so a settled row can pre-date the cutoff.
    walkthrough.update_columns(state: state, updated_at: age.ago)
    walkthrough.reload
  end

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "purges the blob (keeping the row + analysis) for a settled walkthrough past the window" do
    walkthrough = walkthrough_with_blob(state: "analyzed", age: 8.days)
    expect(walkthrough.file).to be_attached

    described_class.perform_now

    walkthrough.reload
    # Row survives with its analysis; only the attachment is purged.
    expect(ChatVideoWalkthrough.exists?(walkthrough.id)).to be true
    expect(walkthrough.analysis).to eq({ "summary" => "s" })
    # purge_later enqueues an Active Storage purge job for the blob.
    purge_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |j|
      j[:job] == ActiveStorage::PurgeJob
    end
    expect(purge_jobs).not_to be_empty
  end

  it "purges failed walkthroughs past the window too" do
    walkthrough = walkthrough_with_blob(state: "failed", age: 8.days)

    expect { described_class.perform_now }.to change {
      ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j[:job] == ActiveStorage::PurgeJob }
    }.by(1)

    expect(ChatVideoWalkthrough.exists?(walkthrough.id)).to be true
  end

  it "keeps the blob for a recently settled walkthrough" do
    walkthrough = walkthrough_with_blob(state: "analyzed", age: 1.day)

    described_class.perform_now

    walkthrough.reload
    expect(walkthrough.file).to be_attached
    purge_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == ActiveStorage::PurgeJob }
    expect(purge_jobs).to be_empty
  end

  it "never purges in-flight walkthroughs regardless of age" do
    uploaded = walkthrough_with_blob(state: "uploaded", age: 30.days, analysis: nil)
    analyzing = walkthrough_with_blob(state: "analyzing", age: 30.days, analysis: nil)

    described_class.perform_now

    [ uploaded, analyzing ].each do |walkthrough|
      walkthrough.reload
      expect(walkthrough.file).to be_attached
    end
    purge_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == ActiveStorage::PurgeJob }
    expect(purge_jobs).to be_empty
  end

  it "does nothing when a settled row past the window has already been pruned" do
    walkthrough = walkthrough_with_blob(state: "analyzed", age: 8.days)
    walkthrough.file.purge
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { described_class.perform_now }.not_to raise_error

    purge_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == ActiveStorage::PurgeJob }
    expect(purge_jobs).to be_empty
  end
end
