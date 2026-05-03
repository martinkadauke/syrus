require "rails_helper"

RSpec.describe RunDiagnosticPruneJob do
  it "deletes RunDiagnostic rows older than RETAIN_AFTER" do
    old   = RunDiagnostic.create!(run: Factories.run, error_class: "X")
    fresh = RunDiagnostic.create!(run: Factories.run, error_class: "X")
    old.update_columns(created_at: (RunDiagnostic::RETAIN_AFTER + 1.day).ago)

    expect { described_class.perform_now }.to change { RunDiagnostic.count }.by(-1)
    expect(RunDiagnostic.exists?(old.id)).to be false
    expect(RunDiagnostic.exists?(fresh.id)).to be true
  end

  it "is a no-op when nothing is prunable" do
    RunDiagnostic.create!(run: Factories.run, error_class: "X")
    expect { described_class.perform_now }.not_to change { RunDiagnostic.count }
  end
end
