require "rails_helper"

RSpec.describe AppEvents do
  it "broadcasts a stable JSON event envelope to the user's app channel" do
    user = Factories.user
    occurred_at = Time.zone.local(2026, 5, 30, 12, 0, 1, 123_000)

    allow(AppUserChannel).to receive(:broadcast_to)

    described_class.broadcast(
      user: user,
      type: "job.updated",
      resource: "job",
      id: 42,
      changed: %i[state pr_number],
      payload: { "state" => "running" },
      occurred_at: occurred_at
    )

    expect(AppUserChannel).to have_received(:broadcast_to).with(
      user,
      {
        "type" => "job.updated",
        "resource" => "job",
        "id" => 42,
        "changed" => %w[state pr_number],
        "occurred_at" => "2026-05-30T12:00:01.123Z",
        "payload" => { "state" => "running" }
      }
    )
  end
end
