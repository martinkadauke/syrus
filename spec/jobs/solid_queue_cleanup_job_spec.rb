require "rails_helper"

RSpec.describe SolidQueueCleanupJob do
  it "delegates to SolidQueue::Job.clear_finished_in_batches with the documented sleep" do
    # SolidQueue::Job's table isn't loaded in this single-DB test setup
    # (CLAUDE.md). Replace the class with a bare stand-in so we can
    # assert the cleanup call without hitting the missing table.
    stub_const("SolidQueue::Job", Class.new { def self.clear_finished_in_batches(*); end })
    expect(SolidQueue::Job).to receive(:clear_finished_in_batches).with(sleep_between_batches: 0.3)
    described_class.perform_now
  end
end
