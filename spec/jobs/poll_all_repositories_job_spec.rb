require "rails_helper"

RSpec.describe PollAllRepositoriesJob do
  it "enqueues PollRepositoryJob for each polling-enabled repository" do
    enabled = Factories.repository(polling_enabled: true)
    other_enabled = Factories.repository(polling_enabled: true)
    Factories.repository(polling_enabled: false)

    expect {
      described_class.perform_now
    }.to have_enqueued_job(PollRepositoryJob).exactly(2).times
      .and have_enqueued_job(PollRepositoryJob).with(enabled.id)
      .and have_enqueued_job(PollRepositoryJob).with(other_enabled.id)
  end
end
