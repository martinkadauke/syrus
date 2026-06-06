require "rails_helper"
require "ostruct"

RSpec.describe RebaseAttemptGuard do
  let(:job) { Factories.job }

  def pr(head_sha: "head", base_sha: "base")
    OpenStruct.new(
      head: OpenStruct.new(sha: head_sha),
      base: OpenStruct.new(sha: base_sha)
    )
  end

  def failed_rebase!(pre_sha: nil, base_sha: nil)
    artifacts = {}
    if pre_sha || base_sha
      artifacts["auto_rebase_result"] = {
        "succeeded" => false,
        "reason" => "conflict",
        "pre_sha" => pre_sha,
        "base_sha" => base_sha
      }.compact
    end
    Workflows::Rebase.instantiate(job: job, artifacts: artifacts).update!(state: "failed")
  end

  it "counts consecutive failed rebase workflows and resets after success" do
    (described_class::ATTEMPT_CAP - 1).times { failed_rebase! }

    expect(described_class.cap_reached?(job)).to eq(false)

    failed_rebase!
    expect(described_class.cap_reached?(job)).to eq(true)

    Workflows::Rebase.instantiate(job: job).update!(state: "succeeded")
    expect(described_class.cap_reached?(job)).to eq(false)
  end

  it "does not count stale failures for a different PR head or base" do
    described_class::ATTEMPT_CAP.times { failed_rebase!(pre_sha: "old-head", base_sha: "base") }

    expect(described_class.cap_reached?(job)).to eq(true)
    expect(described_class.cap_reached?(job, pr: pr(head_sha: "new-head", base_sha: "base"))).to eq(false)
  end
end
