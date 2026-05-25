require "rails_helper"
require "ostruct"

RSpec.describe RebaseLoopGuard do
  let(:job) { Factories.job(pr_mergeable: false) }

  def pr(head_sha: "head", base_sha: nil)
    OpenStruct.new(
      head: OpenStruct.new(sha: head_sha),
      base: OpenStruct.new(sha: base_sha)
    )
  end

  def no_op_rebase(post_sha: "head", base_sha: "base")
    Workflows::Rebase.instantiate(job: job).update!(
      state: "succeeded",
      artifacts: {
        "auto_rebase_result" => {
          "reason" => "rebased",
          "changed" => false,
          "post_sha" => post_sha,
          "base_sha" => base_sha
        }
      }
    )
  end

  it "matches a no-op rebase when the PR head is unchanged and GitHub omits the base sha" do
    no_op_rebase

    expect(described_class.noop_rebase_for?(job: job, pr: pr(base_sha: nil))).to be true
  end

  it "does not match when the PR head advanced after the no-op rebase" do
    no_op_rebase(post_sha: "old-head")

    expect(described_class.noop_rebase_for?(job: job, pr: pr(head_sha: "new-head"))).to be false
  end

  it "does not match when GitHub provides a different base sha" do
    no_op_rebase(base_sha: "old-base")

    expect(described_class.noop_rebase_for?(job: job, pr: pr(base_sha: "new-base"))).to be false
  end
end
