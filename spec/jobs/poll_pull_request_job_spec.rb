require "rails_helper"

RSpec.describe PollPullRequestJob do
  let(:user) { Factories.user(github_token: "ghp_test_token") }
  let(:repository) { Factories.repository(user: user, owner: "acme", name: "widgets") }
  let(:job) do
    j = Factories.job(repository: repository, issue_number: 42)
    j.update!(branch_name: "syrus/issue-42-#{j.id}", pr_number: 7)
    j.initial_run.tap { |r| r.start!; r.succeed!; r.save! }
    j
  end

  let(:slug) { "acme/widgets" }
  let(:pr_url) { "https://api.github.com/repos/acme/widgets/pulls/7" }
  let(:reviews_url) { "https://api.github.com/repos/acme/widgets/pulls/7/reviews" }
  let(:issue_comments_url) { "https://api.github.com/repos/acme/widgets/issues/7/comments" }
  let(:review_comments_url) { "https://api.github.com/repos/acme/widgets/pulls/7/comments" }
  let(:issue_url) { "https://api.github.com/repos/acme/widgets/issues/42" }

  before do
    # Octokit appends ?per_page=100 etc. to every call; match any query string.
    stub_request(:get, issue_url).with(query: hash_including({})).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { number: 42, title: "Add greeting", body: "We need a greeting helper." }.to_json
    )
  end

  def stub_pr(state: "open", merged: false, labels: [], head_sha: "deadbeef0000000000000000000000000000beef")
    stub_request(:get, pr_url).with(query: hash_including({})).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: {
        number: 7,
        state: state,
        merged: merged,
        labels: labels.map { |n| { name: n } },
        head: { sha: head_sha, ref: "syrus/issue-42-#{job.id}" }
      }.to_json
    )
  end

  def stub_check_runs(sha, runs)
    url = "https://api.github.com/repos/acme/widgets/commits/#{sha}/check-runs"
    stub_request(:get, url).with(query: hash_including({})).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { total_count: runs.size, check_runs: runs }.to_json
    )
  end

  def stub_reviews(reviews = [])
    stub_request(:get, reviews_url).with(query: hash_including({})).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: reviews.to_json
    )
  end

  def stub_issue_comments(comments = [])
    stub_request(:get, issue_comments_url).with(query: hash_including({})).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: comments.to_json
    )
  end

  def stub_review_comments(comments = [])
    stub_request(:get, review_comments_url).with(query: hash_including({})).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: comments.to_json
    )
  end

  describe "close conditions" do
    it "closes the Job with reason=pr_merged when the PR is merged" do
      stub_pr(state: "closed", merged: true)
      expect { described_class.perform_now(job.id) }.to change { job.reload.state }.to("closed")
      expect(job.closure_reason).to eq("pr_merged")
    end

    it "closes the Job with reason=pr_closed when the PR is closed but not merged" do
      stub_pr(state: "closed", merged: false)
      described_class.perform_now(job.id)
      expect(job.reload.closure_reason).to eq("pr_closed")
    end

    it "closes the Job with reason=syrus_stop when the PR carries the syrus-stop label" do
      stub_pr(labels: %w[syrus-stop])
      described_class.perform_now(job.id)
      expect(job.reload.closure_reason).to eq("syrus_stop")
    end

    it "closes the Job with reason=pr_approved on a new APPROVED review" do
      stub_pr
      stub_reviews([
        { id: 1, state: "APPROVED", submitted_at: Time.current.iso8601, user: { login: "reviewer" } }
      ])
      described_class.perform_now(job.id)
      expect(job.reload.closure_reason).to eq("pr_approved")
    end
  end

  describe "follow-up dispatch" do
    let(:t1) { Time.parse("2026-05-02 05:00:00 UTC") }
    let(:t2) { Time.parse("2026-05-02 05:05:00 UTC") }

    before do
      stub_pr
      stub_reviews([])
      # CI branch fires too on every poll; default to "no checks" so
      # only the pr_comment branch can do anything in these tests.
      stub_check_runs("deadbeef0000000000000000000000000000beef", [])
    end

    it "creates a pr_comment Run, advances the watermark, composes the prompt" do
      stub_issue_comments([
        { id: 1, body: "Could you also handle empty strings?",
          user: { login: "reviewer" }, created_at: t1.iso8601 }
      ])
      stub_review_comments([
        { id: 2, body: "Breaks on nil", path: "lib/greet.rb", line: 5,
          diff_hunk: "@@\n+ \"Hello, #{nil}!\"",
          user: { login: "reviewer" }, created_at: t2.iso8601, pull_request_review_id: nil }
      ])

      expect {
        described_class.perform_now(job.id)
      }.to change { job.runs.where(trigger_kind: "pr_comment").count }.by(1)

      run = job.runs.where(trigger_kind: "pr_comment").last
      expect(run.prompt).to include("Could you also handle empty strings?")
      expect(run.prompt).to include("Breaks on nil")
      expect(run.prompt).to include("lib/greet.rb:5")
      expect(job.reload.last_seen_comment_at.utc).to be_within(1.second).of(t2)
    end

    it "DOES process operator-authored comments (Syrus runs under the operator's PAT today; the operator IS the reviewer)" do
      stub_issue_comments([
        { id: 1, body: "extract this into a helper",
          user: { login: "operator" }, created_at: t1.iso8601 }
      ])
      stub_review_comments([])

      expect {
        described_class.perform_now(job.id)
      }.to change { job.runs.where(trigger_kind: "pr_comment").count }.by(1)
    end

    it "respects the loop guard (5 pr_comment runs already)" do
      5.times { Run.create!(job: job, trigger_kind: "pr_comment", state: "succeeded") }
      stub_issue_comments([
        { id: 1, body: "more feedback", user: { login: "reviewer" }, created_at: t1.iso8601 }
      ])
      stub_review_comments([])

      expect {
        described_class.perform_now(job.id)
      }.not_to change { job.runs.count }
    end

    it "skips when an active pr_comment Run is already pending" do
      Run.create!(job: job, trigger_kind: "pr_comment", state: "queued")
      stub_issue_comments([
        { id: 1, body: "more feedback", user: { login: "reviewer" }, created_at: t1.iso8601 }
      ])
      stub_review_comments([])

      expect {
        described_class.perform_now(job.id)
      }.not_to change { job.runs.where(trigger_kind: "pr_comment").count }
    end

    it "is a no-op when there are no new comments" do
      stub_issue_comments([])
      stub_review_comments([])
      expect {
        described_class.perform_now(job.id)
      }.not_to change { job.runs.count }
    end
  end

  describe "ci_failure dispatch" do
    let(:sha) { "abc1234567890000000000000000000000000000" }

    before do
      stub_pr(head_sha: sha)
      stub_reviews([])
      stub_issue_comments([])
      stub_review_comments([])
    end

    it "creates a ci_failure Run with a prompt that names the failing checks" do
      stub_check_runs(sha, [
        { name: "test", status: "completed", conclusion: "failure",
          html_url: "https://github.com/acme/widgets/runs/100",
          output: { summary: "RSpec: 2 examples, 1 failure (greet_spec.rb:14)" } },
        { name: "lint", status: "completed", conclusion: "success",
          html_url: "https://github.com/acme/widgets/runs/101", output: { summary: "0 issues" } }
      ])

      expect {
        described_class.perform_now(job.id)
      }.to change { job.runs.where(trigger_kind: "ci_failure").count }.by(1)

      run = job.runs.where(trigger_kind: "ci_failure").last
      expect(run.prompt).to include("acme/widgets#7")
      expect(run.prompt).to include("test")
      expect(run.prompt).to include("RSpec: 2 examples, 1 failure (greet_spec.rb:14)")
      expect(run.prompt).not_to include("0 issues")    # successes are excluded
      expect(job.reload.last_ci_handled_sha).to eq(sha)
    end

    it "is a no-op when all checks are passing" do
      stub_check_runs(sha, [
        { name: "test", status: "completed", conclusion: "success",
          html_url: "u", output: { summary: "ok" } }
      ])
      expect { described_class.perform_now(job.id) }.not_to change { job.runs.where(trigger_kind: "ci_failure").count }
    end

    it "is a no-op when checks are still in_progress (don't act on partial state)" do
      stub_check_runs(sha, [
        { name: "test", status: "in_progress", conclusion: nil,
          html_url: "u", output: { summary: nil } }
      ])
      expect { described_class.perform_now(job.id) }.not_to change { job.runs.where(trigger_kind: "ci_failure").count }
    end

    it "doesn't re-react to the same head SHA twice" do
      stub_check_runs(sha, [
        { name: "test", status: "completed", conclusion: "failure",
          html_url: "u", output: { summary: "fail" } }
      ])
      job.update!(last_ci_handled_sha: sha)

      expect { described_class.perform_now(job.id) }.not_to change { job.runs.where(trigger_kind: "ci_failure").count }
    end

    it "skips when an active ci_failure Run is already pending" do
      Run.create!(job: job, trigger_kind: "ci_failure", state: "queued")
      stub_check_runs(sha, [
        { name: "test", status: "completed", conclusion: "failure",
          html_url: "u", output: { summary: "fail" } }
      ])
      expect { described_class.perform_now(job.id) }.not_to change { job.runs.where(trigger_kind: "ci_failure").count }
    end

    it "respects the cap (3 ci_failure runs already)" do
      3.times { Run.create!(job: job, trigger_kind: "ci_failure", state: "succeeded") }
      stub_check_runs(sha, [
        { name: "test", status: "completed", conclusion: "failure",
          html_url: "u", output: { summary: "fail" } }
      ])
      expect { described_class.perform_now(job.id) }.not_to change { job.runs.where(trigger_kind: "ci_failure").count }
    end

    it "treats timed_out / action_required / cancelled as failures, ignores neutral / skipped" do
      stub_check_runs(sha, [
        { name: "build",  status: "completed", conclusion: "timed_out",       html_url: "u1", output: { summary: "timed out at 30m" } },
        { name: "deploy", status: "completed", conclusion: "action_required", html_url: "u2", output: { summary: "approve required" } },
        { name: "snyk",   status: "completed", conclusion: "neutral",         html_url: "u3", output: { summary: "no issues" } },
        { name: "skipme", status: "completed", conclusion: "skipped",         html_url: "u4", output: { summary: nil } }
      ])

      expect {
        described_class.perform_now(job.id)
      }.to change { job.runs.where(trigger_kind: "ci_failure").count }.by(1)

      run = job.runs.where(trigger_kind: "ci_failure").last
      expect(run.prompt).to include("build").and include("deploy")
      expect(run.prompt).not_to include("snyk")    # neutral isn't a failure
      expect(run.prompt).not_to include("skipme")
    end
  end

  describe "guards" do
    it "no-ops when the Job is already closed" do
      stub_pr  # Need it because before block doesn't always run for guards
      job.close_with_reason!("manual")
      expect {
        described_class.perform_now(job.id)
      }.not_to change { job.runs.count }
      # PR fetch shouldn't even happen
      expect(WebMock).not_to have_requested(:get, pr_url)
    end

    it "no-ops when the Job has no PR yet" do
      stub_pr
      bare = Factories.job(repository: repository, issue_number: 99)
      expect {
        described_class.perform_now(bare.id)
      }.not_to change { bare.runs.count }
    end
  end
end
