require "rails_helper"

RSpec.describe WorkEngineReconcilerActivityPruneJob do
  it "deletes reconciler activity events older than the retention window" do
    old = fresh = nil
    travel_to Time.zone.parse("2026-08-09 12:00:00 UTC") do
      old = WorkEngineReconcilerActivityEvent.record!(
        event_type: "run_finished",
        source: "spec",
        message: "old",
        occurred_at: (WorkEngineReconcilerActivityEvent::RETAIN_AFTER + 1.second).ago
      )
      fresh = WorkEngineReconcilerActivityEvent.record!(
        event_type: "run_finished",
        source: "spec",
        message: "fresh",
        occurred_at: WorkEngineReconcilerActivityEvent::RETAIN_AFTER.ago
      )

      expect { described_class.perform_now }.to change { WorkEngineReconcilerActivityEvent.count }.by(-1)
    end
    expect(WorkEngineReconcilerActivityEvent.exists?(old.id)).to be(false)
    expect(WorkEngineReconcilerActivityEvent.exists?(fresh.id)).to be(true)
  end
end
