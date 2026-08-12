require "rails_helper"

RSpec.describe PollInputSourceJob do
  let(:user) { Factories.user(github_token: "ghp_test_token") }
  let(:repository) { Factories.repository(user: user, polling_enabled: true) }
  let(:source) { repository.github_input_source }

  it "calls poll! on the input source" do
    allow(source).to receive(:poll!)
    allow(InputSource).to receive(:find_by).with(id: source.id).and_return(source)
    expect(source).to receive(:poll!)
    described_class.perform_now(source.id)
  end

  it "does nothing when the source does not exist" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "skips a disabled source unless forced" do
    source.update!(polling_enabled: false)
    allow(InputSource).to receive(:find_by).with(id: source.id).and_return(source)

    expect(source).not_to receive(:poll!)
    described_class.perform_now(source.id)
  end

  it "polls a disabled source when force: true" do
    source.update!(polling_enabled: false)
    allow(InputSource).to receive(:find_by).with(id: source.id).and_return(source)

    expect(source).to receive(:poll!)
    described_class.perform_now(source.id, force: true)
  end

  it "logs source context when polling hits a regexp timeout" do
    allow(source).to receive(:poll!).and_raise(Regexp::TimeoutError, "regexp timed out")
    allow(InputSource).to receive(:find_by).with(id: source.id).and_return(source)
    allow(Rails.logger).to receive(:error).and_call_original

    expect { described_class.perform_now(source.id) }.to raise_error(Regexp::TimeoutError)

    expect(Rails.logger).to have_received(:error).with(
      include(
        "[PollInputSourceJob] regexp timeout",
        "source_id=#{source.id}",
        "source_type=InputSources::Github",
        "repository=#{repository.slug}"
      )
    )
  end
end
