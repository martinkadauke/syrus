require "rails_helper"

RSpec.describe SyncEnabledForksJob do
  include ActiveJob::TestHelper

  let(:user) { Factories.user }
  let(:upstream) { Factories.repository(user: user, owner: "upstream-org", name: "project") }

  def fork_repo(name:, auto_sync:, with_upstream: true)
    Factories.repository(
      user: user,
      owner: "fork-user",
      name: name,
      upstream_repository: with_upstream ? upstream : nil,
      fork_auto_sync_enabled: auto_sync
    )
  end

  before { clear_enqueued_jobs }

  it "enqueues SyncForkJob only for auto-sync-enabled forks with an in-instance upstream" do
    enabled = fork_repo(name: "enabled", auto_sync: true)
    fork_repo(name: "disabled", auto_sync: false)
    fork_repo(name: "no-upstream", auto_sync: true, with_upstream: false)

    described_class.perform_now

    enqueued = enqueued_jobs.select { |j| j["job_class"] == "SyncForkJob" }
    repo_ids = enqueued.map { |j| j["arguments"].first }
    expect(repo_ids).to contain_exactly(enabled.id)
  end
end
