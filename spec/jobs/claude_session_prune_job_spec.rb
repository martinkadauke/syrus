require "rails_helper"

RSpec.describe ClaudeSessionPruneJob do
  it "deletes ClaudeSessions for terminal Runs older than the retention window" do
    old_run = Factories.job.initial_run.tap { |r| r.start!; r.fail!; r.save! }
    new_run = Factories.job.initial_run.tap { |r| r.start!; r.fail!; r.save! }
    active_run = Factories.job.initial_run  # queued

    old_session    = ClaudeSession.create!(run: old_run,    session_id: "old",    transcript_jsonl: "x")
    new_session    = ClaudeSession.create!(run: new_run,    session_id: "new",    transcript_jsonl: "x")
    active_session = ClaudeSession.create!(run: active_run, session_id: "active", transcript_jsonl: "x")
    old_session.update_columns(updated_at: (ClaudeSession::RETAIN_AFTER_TERMINAL + 1.day).ago)
    active_session.update_columns(updated_at: 1.year.ago)  # old, but parent is active → keep

    expect {
      described_class.perform_now
    }.to change { ClaudeSession.count }.by(-1)

    expect(ClaudeSession.exists?(old_session.id)).to be false
    expect(ClaudeSession.exists?(new_session.id)).to be true
    expect(ClaudeSession.exists?(active_session.id)).to be true
  end

  it "is a no-op when nothing is prunable" do
    expect { described_class.perform_now }.not_to change { ClaudeSession.count }
  end
end
