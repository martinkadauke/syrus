require "rails_helper"

RSpec.describe PollAllInputSourcesJob do
  it "does not enqueue disabled source providers" do
    repository = Factories.repository
    source = repository.github_input_source
    PluginRecord.find_by!(name: "github_source").update!(enabled: false)

    expect {
      described_class.perform_now
    }.not_to have_enqueued_job(PollInputSourceJob).with(source.id)
  end
end
