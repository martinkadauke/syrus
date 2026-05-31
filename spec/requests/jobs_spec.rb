require "rails_helper"

RSpec.describe "Jobs", type: :request do
  let(:user)  { Factories.user }
  let(:other) { Factories.user }
  # auto_merge_enabled: true so approve specs don't all need to set
  # it explicitly. The single "rejects approve on auto-merge-disabled
  # repo" spec creates its own repo with the flag off.
  let(:repository) { Factories.repository(user: user, owner: "acme", name: "widgets", auto_merge_enabled: true) }
  let(:job) { Factories.job(repository: repository, issue_number: 42) }

  around do |example|
    old_data_root = ENV["SYRUS_DATA_ROOT"]
    data_root = Dir.mktmpdir("syrus-jobs-spec")
    ENV["SYRUS_DATA_ROOT"] = data_root
    example.run
  ensure
    ENV["SYRUS_DATA_ROOT"] = old_data_root
    FileUtils.rm_rf(data_root) if data_root
  end

  def github_issue_with_labels(*names)
    labels = names.map { |name| Struct.new(:name, keyword_init: true).new(name: name) }
    Struct.new(:labels, keyword_init: true).new(labels: labels)
  end

  describe "SPA job routes" do
    before { sign_in_as(user) }

    it "renders the React shell for job detail" do
      get job_path(job)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="syrus-spa-root"')
    end

    it "renders the React shell for the source browser route" do
      get source_job_path(job)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="syrus-spa-root"')
    end
  end

  describe "retired legacy Job detail route" do
    it "does not route /jobs/:id/legacy" do
      expect {
        Rails.application.routes.recognize_path("/jobs/#{job.id}/legacy", method: :get)
      }.to raise_error(ActionController::RoutingError)
    end
  end

  describe "approval actions" do
    before { sign_in_as(user) }

    # Regression: approving a Job whose repo has auto_merge_enabled
    # off used to silently succeed locally, then get wiped on the
    # next landing tick when AutoMergeGate raised
    # "repository has not enabled auto-merge" -> fail_landing ->
    # approved_at cleared. Surface the misconfiguration at approve
    # time instead.
    it "refuses to approve a Job whose repository has auto-merge disabled" do
      no_automerge_repo = Factories.repository(user: user, owner: "acme", name: "lib",
                                                auto_merge_enabled: false)
      no_automerge_job = Factories.job(repository: no_automerge_repo, issue_number: 99)
      no_automerge_job.update!(state: "implemented")

      post approve_job_path(no_automerge_job)

      expect(response).to redirect_to(job_path(no_automerge_job))
      expect(flash[:alert]).to include("Auto-merge is disabled for acme/lib")
      expect(no_automerge_job.reload.state).to eq("implemented")
      expect(no_automerge_job.approved_at).to be_nil
    end

    it "approves an implemented job" do
      user.update!(name: "Thomas")
      job.update!(state: "implemented")

      freeze_time do
        post approve_job_path(job)
      end

      expect(response).to redirect_to(job_path(job))
      expect(job.reload.state).to eq("approved")
      expect(job.approved_at).to be_present
      expect(job.approved_via).to eq("operator")
      expect(job.approved_by_user).to eq(user)
    end

    it "unapproves an approved job before landing starts" do
      job.update!(state: "implemented")
      job.approve!(via: "operator", by_user: user)

      post unapprove_job_path(job)

      expect(response).to redirect_to(job_path(job))
      expect(job.reload.state).to eq("implemented")
      expect(job.approved_at).to be_nil
      expect(job.approved_via).to be_nil
      expect(job.approved_by_user).to be_nil
      expect(job.approval_evidence).to eq({})
    end

    it "refuses to unapprove a landing job" do
      job.update!(state: "implemented")
      job.approve!(via: "operator", by_user: user)
      job.start_landing!

      post unapprove_job_path(job)

      expect(response).to redirect_to(job_path(job))
      expect(flash[:alert]).to include("Only approved Jobs")
      expect(job.reload.state).to eq("landing")
    end

    it "files an APPROVE review on GitHub when the Job has a PR and the repo opts in" do
      job.update!(state: "implemented", pr_number: 123)
      client = instance_double(GithubClient)
      allow(GithubClient).to receive(:for).with(repository: repository, user: user).and_return(client)
      expect(client).to receive(:create_pr_review)
        .with("acme/widgets", 123, event: "APPROVE", body: a_string_including("Syrus"))
        .and_return(Struct.new(:id).new(987))

      post approve_job_path(job)

      expect(response).to redirect_to(job_path(job))
      expect(flash[:notice]).to include("GitHub review left")
      expect(job.reload.approval_evidence).to include("github_review_id" => 987)
    end

    it "skips the GitHub review when the repo opts out" do
      repository.update!(approval_propagates_to_github: false)
      job.update!(state: "implemented", pr_number: 123)
      expect(GithubClient).not_to receive(:for)

      post approve_job_path(job)

      expect(job.reload.state).to eq("approved")
      expect(flash[:notice]).to eq("Job approved.")
    end

    it "still approves Syrus-side if the GitHub review write fails" do
      job.update!(state: "implemented", pr_number: 123)
      client = instance_double(GithubClient)
      allow(GithubClient).to receive(:for).with(repository: repository, user: user).and_return(client)
      allow(client).to receive(:create_pr_review)
        .and_raise(Octokit::UnprocessableEntity.new(body: { message: "Pull request author can't approve their own pull request" }))

      post approve_job_path(job)

      expect(response).to redirect_to(job_path(job))
      expect(job.reload.state).to eq("approved")
      expect(flash[:notice]).to include("GitHub review failed")
    end

    it "dismisses the GitHub review on unapprove" do
      job.update!(state: "implemented", pr_number: 123)
      job.approve!(via: "operator", by_user: user, evidence: { "github_review_id" => 555 })
      client = instance_double(GithubClient)
      allow(GithubClient).to receive(:for).with(repository: repository, user: user).and_return(client)
      expect(client).to receive(:dismiss_pr_review)
        .with("acme/widgets", 123, 555, message: a_string_including("Syrus"))

      post unapprove_job_path(job)

      expect(response).to redirect_to(job_path(job))
      expect(job.reload.state).to eq("implemented")
      expect(flash[:notice]).to include("GitHub review dismissed")
    end
  end

  describe "tag actions" do
    before { sign_in_as(user) }

    it "adds an existing tag by name" do
      tag = Factories.tag(user: user, name: "urgent", color: "red")

      post tags_job_path(job), params: { tag_name: "urgent" }

      expect(job.reload.tags).to contain_exactly(tag)
      expect(response).to redirect_to(job_path(job))
    end

    it "creates a new tag inline when adding it to a job" do
      expect {
        post tags_job_path(job), params: { tag_name: "theme:cleanup" }
      }.to change { user.tags.count }.by(1)

      expect(job.reload.tags.pluck(:name)).to eq([ "theme:cleanup" ])
    end

    it "removes a tag from the job without deleting the tag" do
      tag = Factories.tag(user: user, name: "urgent", color: "red")
      job.tags << tag

      delete tag_job_path(job, tag_id: tag.id)

      expect(job.reload.tags).to be_empty
      expect(Tag.exists?(tag.id)).to be(true)
    end
  end

  describe "GET /jobs/:id/runs/:run_id/grade_log" do
    let(:workflow) { job.latest_workflow }
    # In the per-grader-Step world the initial chain has a
    # grader_fanout placeholder that materializes "grader" Steps at
    # runtime. Tests bypass the fanout and manually create a grader
    # Step + Run so the endpoint has a real Step kind to match.
    let(:grade_step) do
      collect = workflow.steps.find_by!(kind: "grader_collect")
      collect.update!(position: collect.position + 1)
      Step.create!(workflow: workflow, kind: "grader",
                   position: collect.position - 1,
                   loop_id: collect.loop_id,
                   iteration: collect.iteration,
                   details: { "name" => "tests", "command" => "echo ok" })
    end
    let(:grade_run) { Run.create!(job: job, step: grade_step, trigger_kind: "initial", iteration: 1, state: "failed") }

    def write_grade_log(run, name, contents)
      path = WorkflowWorkspace.path_for(run.workflow).join(".syrus", "grade-output", "iteration-#{run.iteration}", "#{name}.log")
      FileUtils.mkdir_p(path.dirname)
      path.write(contents)
    end

    it "requires authentication" do
      get run_grade_log_job_path(job, run_id: grade_run.id, name: "tests")

      expect(response).to redirect_to(new_session_path)
    end

    it "streams the requested grade log for the job owner" do
      sign_in_as(user)
      write_grade_log(grade_run, "tests", "rspec output\n")

      get run_grade_log_job_path(job, run_id: grade_run.id, name: "tests")

      expect(response).to be_successful
      expect(response.media_type).to eq("text/plain")
      expect(response.body).to eq("rspec output\n")
    end

    it "allows admins to stream another user's grade log" do
      admin = user
      foreign_repo = Factories.repository(user: other)
      foreign_job = Factories.job(repository: foreign_repo, issue_number: 7)
      foreign_wf = foreign_job.latest_workflow
      foreign_collect = foreign_wf.steps.find_by!(kind: "grader_collect")
      foreign_collect.update!(position: foreign_collect.position + 1)
      foreign_grade_step = Step.create!(workflow: foreign_wf, kind: "grader",
                                        position: foreign_collect.position - 1,
                                        loop_id: foreign_collect.loop_id,
                                        iteration: foreign_collect.iteration,
                                        details: { "name" => "tests", "command" => "echo ok" })
      foreign_grade_run = Run.create!(job: foreign_job, step: foreign_grade_step, trigger_kind: "initial", iteration: 1, state: "failed")
      write_grade_log(foreign_grade_run, "tests", "foreign output\n")
      sign_in_as(admin)

      get run_grade_log_job_path(foreign_job, run_id: foreign_grade_run.id, name: "tests")

      expect(response).to be_successful
      expect(response.body).to eq("foreign output\n")
    end

    it "403s for a signed-in non-owner who is not an admin" do
      user
      sign_in_as(other)

      get run_grade_log_job_path(job, run_id: grade_run.id, name: "tests")

      expect(response).to have_http_status(:forbidden)
    end

    it "renders a fallback when the workspace log has been pruned" do
      sign_in_as(user)

      get run_grade_log_job_path(job, run_id: grade_run.id, name: "tests")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("no longer available")
    end
  end

  describe "POST /jobs/:id/run_again (retry)" do
    before { sign_in_as(user) }

    it "creates a new Run with trigger_kind=retry on the existing Job and enqueues RunJob" do
      job.initial_run.tap { |r| r.start!; r.succeed!; r.save! }
      expect {
        post run_again_job_path(job)
      }.to change { job.runs.count }.by(1)
        .and have_enqueued_job(RunJob)

      new_run = job.runs.last
      expect(new_run.trigger_kind).to eq("retry")
      expect(new_run.state).to eq("queued")
      expect(response).to redirect_to(job_path(job, tab: "workflows"))
    end

    it "stores retry context in workflow artifacts when provided" do
      job.initial_run.tap { |r| r.start!; r.succeed!; r.save! }
      post run_again_job_path(job), params: { retry_context: "Please fix the failing tests in spec/models/user_spec.rb." }

      workflow = job.workflows.where(trigger_kind: "retry").last
      expect(workflow.artifacts["replay_context"]).to eq("Please fix the failing tests in spec/models/user_spec.rb.")
    end

    it "keeps replay_context as a compatibility alias" do
      job.initial_run.tap { |r| r.start!; r.succeed!; r.save! }
      post run_again_job_path(job), params: { replay_context: "Please keep the old client working." }

      workflow = job.workflows.where(trigger_kind: "retry").last
      expect(workflow.artifacts["replay_context"]).to eq("Please keep the old client working.")
    end

    it "stores no artifacts when retry_context is blank" do
      job.initial_run.tap { |r| r.start!; r.succeed!; r.save! }
      post run_again_job_path(job), params: { retry_context: "  " }

      workflow = job.workflows.where(trigger_kind: "retry").last
      expect(workflow.artifacts).to be_nil
    end

    it "refreshes the source issue label before choosing the retry steps" do
      user.update!(github_token: "ghp_test_token")
      job.initial_run.tap { |r| r.start!; r.succeed!; r.save! }
      client = instance_double(GithubClient)
      allow(GithubClient).to receive(:for).with(repository: repository, user: user).and_return(client)
      allow(client).to receive(:fetch_issue)
        .with("acme/widgets", 42)
        .and_return(github_issue_with_labels("syrus", Workflows::SKIP_PREPARE_LABEL))

      post run_again_job_path(job)

      workflow = job.reload.workflows.where(trigger_kind: "retry").last
      expect(job).to be_skip_prepare
      expect(workflow.steps.order(:position).pluck(:kind)).to eq(%w[ implement grader_fanout grader_collect summarize pr_open ])
    end

    it "retries with an explicitly selected alternate configured agent" do
      user.update!(claude_oauth_token: "oat-test", codex_auth_mode: "api_key", codex_api_key: "sk-test")
      job.initial_run.update!(
        state: "succeeded",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        agent_provider: "claude"
      )
      job.latest_workflow.update!(state: "succeeded", started_at: 2.minutes.ago, finished_at: 1.minute.ago)

      expect {
        post run_again_job_path(job), params: { agent_provider: "codex" }
      }.to change { job.workflows.where(trigger_kind: "retry").count }.by(1)

      workflow = job.workflows.where(trigger_kind: "retry").last
      expect(job.reload.agent_provider).to eq("codex")
      expect(workflow.agent_provider).to eq("codex")
      expect(workflow.first_step.runs.last.agent_provider).to eq("codex")
      expect(flash[:notice]).to match(/with Codex/)
    end

    it "rejects an explicit provider that was used by the latest run" do
      user.update!(claude_oauth_token: "oat-test", codex_auth_mode: "api_key", codex_api_key: "sk-test")
      job.initial_run.update!(
        state: "succeeded",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        agent_provider: "claude"
      )
      job.latest_workflow.update!(state: "succeeded", started_at: 2.minutes.ago, finished_at: 1.minute.ago)

      expect {
        post run_again_job_path(job), params: { agent_provider: "claude" }
      }.not_to change { job.workflows.where(trigger_kind: "retry").count }
      expect(flash[:alert]).to match(/not available/)
    end

    it "rejects an explicit provider that is not configured" do
      user.update!(claude_oauth_token: "oat-test", codex_api_key: nil)
      job.initial_run.update!(
        state: "succeeded",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        agent_provider: "claude"
      )
      job.latest_workflow.update!(state: "succeeded", started_at: 2.minutes.ago, finished_at: 1.minute.ago)

      expect {
        post run_again_job_path(job), params: { agent_provider: "codex" }
      }.not_to change { job.workflows.where(trigger_kind: "retry").count }
      expect(flash[:alert]).to match(/not available/)
    end

    it "refuses when the Job is closed" do
      job.close_with_reason!("manual")
      expect {
        post run_again_job_path(job)
      }.not_to change { job.runs.count }
      expect(flash[:alert]).to match(/use Start over/)
    end

    it "refuses when an active Run is already in progress" do
      job.initial_run  # queued by default
      expect {
        post run_again_job_path(job)
      }.not_to change { job.runs.count }
      expect(flash[:alert]).to match(/already in progress/)
    end
  end

  describe "POST /jobs/:id/restart (hard reset)" do
    before { sign_in_as(user) }

    it "closes the existing Job and creates a new one with a fresh initial Run" do
      job.initial_run.tap { |r| r.start!; r.succeed!; r.save! }
      original_id = job.id

      expect {
        post restart_job_path(job)
      }.to change(Job, :count).by(1)
        .and have_enqueued_job(RunJob)

      job.reload
      expect(job.state).to eq("closed")
      expect(job.closure_reason).to eq("replaced")

      new_job = Job.where(repository_id: repository.id, issue_number: 42).order(:created_at).last
      expect(new_job.id).not_to eq(original_id)
      expect(new_job.runs.first.trigger_kind).to eq("initial")
      expect(response).to redirect_to(job_path(new_job))
    end

    it "cancels active runs on the original before creating the new one" do
      job.initial_run  # queued
      post restart_job_path(job)
      expect(job.runs.first.reload.state).to eq("cancelled")
    end

    it "still creates a new Job when the original is already closed" do
      job.close_with_reason!("manual")
      expect {
        post restart_job_path(job)
      }.to change(Job, :count).by(1)
    end

    it "refreshes the source issue label before creating the replacement Job" do
      user.update!(github_token: "ghp_test_token")
      job.initial_run.tap { |r| r.start!; r.succeed!; r.save! }
      client = instance_double(GithubClient)
      allow(GithubClient).to receive(:for).with(repository: repository, user: user).and_return(client)
      allow(client).to receive(:fetch_issue)
        .with("acme/widgets", 42)
        .and_return(github_issue_with_labels("syrus", Workflows::SKIP_PREPARE_LABEL))

      post restart_job_path(job)

      new_job = Job.where(repository_id: repository.id, issue_number: 42).order(:created_at).last
      expect(new_job).to be_skip_prepare
      expect(new_job.workflows.first.steps.order(:position).pluck(:kind)).to eq(%w[ implement grader_fanout grader_collect summarize pr_open ])
    end
  end

  describe "POST /jobs/:id/cancel" do
    before { sign_in_as(user) }

    it "cancels active runs and closes the Job thread" do
      run = job.initial_run
      run.start!; run.save!

      post cancel_job_path(job)

      job.reload
      run.reload
      expect(run.state).to eq("cancelled")
      expect(job.state).to eq("closed")
      expect(job.closure_reason).to eq("cancelled")
      expect(response).to redirect_to(job_path(job))
    end

    it "refuses to cancel an already-closed Job" do
      job.close_with_reason!("manual")
      post cancel_job_path(job)
      expect(flash[:alert]).to match(/already closed/)
    end
  end

  describe "POST /jobs/:id/stop_run" do
    before { sign_in_as(user) }

    it "cancels the target Run without closing the Job" do
      run = job.initial_run
      run.start!; run.save!

      post stop_run_job_path(job, run_id: run.id)

      run.reload
      job.reload
      expect(run.state).to eq("cancelled")
      expect(job).to be_open
      expect(response).to redirect_to(job_path(job))
      expect(flash[:notice]).to match(/stopped/i)
    end

    it "works on a queued (not yet started) Run" do
      run = job.initial_run  # state=queued by default

      post stop_run_job_path(job, run_id: run.id)

      expect(run.reload.state).to eq("cancelled")
      expect(job.reload).to be_open
    end

    it "refuses to stop an already-terminal Run" do
      run = job.initial_run
      run.start!; run.succeed!; run.save!

      post stop_run_job_path(job, run_id: run.id)

      expect(run.reload.state).to eq("succeeded")
      expect(flash[:alert]).to match(/not active/i)
    end

    it "returns not found for a run_id that doesn't belong to this Job" do
      other_job = Factories.job(repository: repository, issue_number: 99)
      stranger = other_job.initial_run

      post stop_run_job_path(job, run_id: stranger.id)

      expect(stranger.reload.state).to eq("queued")
      expect(flash[:alert]).to match(/not found/i)
    end

    it "404s for another user's job" do
      foreign_repo = Factories.repository(user: other)
      foreign_job  = Factories.job(repository: foreign_repo, issue_number: 1)
      run          = foreign_job.initial_run

      post stop_run_job_path(foreign_job, run_id: run.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /jobs/:id/retry_step" do
    before { sign_in_as(user) }

    let(:workflow) { job.workflows.last }
    let(:failed_step) {
      workflow.steps.find_by(kind: "summarize").tap do |s|
        # Create a failed Run on the step + transition both to failed.
        run = s.runs.create!(job: job, trigger_kind: "initial",
                             state: "failed", started_at: 1.minute.ago,
                             finished_at: Time.current,
                             agent_outcome: "error_max_turns")
        s.update!(state: "failed", started_at: 1.minute.ago, finished_at: Time.current)
      end
    }

    before do
      # Bring the workflow into a failed state with the second step
      # failed. Bypass AASM (state already includes "failed" terminal).
      workflow.update!(state: "failed", started_at: 1.minute.ago, finished_at: Time.current)
      failed_step
    end

    it "reopens the Workflow + Step and creates a fresh Run on the failed step" do
      expect {
        post retry_step_job_path(job, workflow_id: workflow.id)
      }.to change { failed_step.runs.count }.by(1)

      expect(workflow.reload.state).to eq("running")
      expect(failed_step.reload.state).to eq("queued")
      expect(response).to redirect_to(job_path(job))
      expect(flash[:notice]).to match(/Retrying summarize/)
    end

    it "preserves the workflow agent provider on the retry Run" do
      workflow.update!(agent_provider: "codex")

      post retry_step_job_path(job, workflow_id: workflow.id)

      expect(failed_step.runs.order(:created_at).last.agent_provider).to eq("codex")
    end

    it "refuses when the workflow's workspace was already cleaned up" do
      workflow.update_columns(cleaned_up_at: Time.current)
      expect {
        post retry_step_job_path(job, workflow_id: workflow.id)
      }.not_to change(Run, :count)
      expect(flash[:alert]).to eq("Workspace already cleaned up — use Start over.")
    end

    it "refuses when the workflow isn't failed" do
      workflow.update!(state: "running", finished_at: nil)
      post retry_step_job_path(job, workflow_id: workflow.id)
      expect(flash[:alert]).to match(/not in a failed state/i)
    end

    it "404s for another user's job" do
      foreign_repo = Factories.repository(user: other)
      foreign_job  = Factories.job(repository: foreign_repo, issue_number: 1)
      foreign_wf   = foreign_job.workflows.last
      post retry_step_job_path(foreign_job, workflow_id: foreign_wf.id)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /jobs/:id/poll_feedback" do
    before { sign_in_as(user) }

    it "enqueues PollPullRequestJob for an open Job with a PR (with manual: true to bypass cap)" do
      job.update!(pr_number: 42)
      expect {
        post poll_feedback_job_path(job)
      }.to have_enqueued_job(PollPullRequestJob).with(job.id, manual: true)
      expect(response).to redirect_to(job_path(job))
    end

    it "switches the job and passes an explicitly selected configured agent to the PR poller" do
      user.update!(claude_oauth_token: "oat-test", codex_auth_mode: "api_key", codex_api_key: "sk-test")
      job.update!(pr_number: 42, agent_provider: "claude")

      expect {
        post poll_feedback_job_path(job), params: { agent_provider: "codex" }
      }.to have_enqueued_job(PollPullRequestJob).with(job.id, manual: true, agent_provider: "codex")

      expect(job.reload.agent_provider).to eq("codex")
      expect(flash[:notice]).to match(/with Codex/)
    end

    it "rejects an explicitly selected agent that is not configured" do
      user.update!(claude_oauth_token: "oat-test", codex_api_key: nil)
      job.update!(pr_number: 42, agent_provider: "claude")

      expect {
        post poll_feedback_job_path(job), params: { agent_provider: "codex" }
      }.not_to have_enqueued_job(PollPullRequestJob)

      expect(job.reload.agent_provider).to eq("claude")
      expect(flash[:alert]).to match(/not configured/)
    end

    it "refuses on a Job with no PR" do
      expect {
        post poll_feedback_job_path(job)
      }.not_to have_enqueued_job(PollPullRequestJob)
      expect(flash[:alert]).to match(/PR/)
    end

    it "refuses on a closed Job" do
      job.update!(pr_number: 42)
      job.close_with_reason!("manual")
      expect {
        post poll_feedback_job_path(job)
      }.not_to have_enqueued_job(PollPullRequestJob)
    end
  end

  describe "POST /jobs/:id/reopen" do
    before { sign_in_as(user) }

    it "transitions a closed Job back to open and clears closure_reason + finished_at" do
      job.close_with_reason!("cancelled")

      post reopen_job_path(job)

      job.reload
      expect(job.state).to eq("triaging")
      expect(job.closure_reason).to be_nil
      expect(job.finished_at).to be_nil
      expect(response).to redirect_to(job_path(job))
      expect(flash[:notice]).to match(/reopened/)
    end

    it "warns when reopening a thread closed by syrus_stop" do
      job.close_with_reason!("syrus_stop")
      post reopen_job_path(job)
      expect(flash[:notice]).to match(/syrus-stop/)
    end

    it "warns when reopening a thread closed by pr_merged" do
      job.close_with_reason!("pr_merged")
      post reopen_job_path(job)
      expect(flash[:notice]).to match(/PR state/)
    end

    it "refuses on an open Job" do
      post reopen_job_path(job)
      expect(job.reload).to be_open
      expect(flash[:alert]).to match(/isn't closed/)
    end
  end

  describe "POST /jobs/:id/resume" do
    before { sign_in_as(user) }

    let(:failed_run) do
      r = job.initial_run
      r.start!; r.fail!; r.save!
      r
    end

    it "instantiates a Resume workflow carrying parent_session_id from a Codex-backed captured session" do
      ClaudeSession.create!(resumable: failed_run, provider: "codex",
                            session_id: "uuid-deadbeef", transcript_jsonl: "{}\n")

      expect {
        post resume_job_path(job, source_run_id: failed_run.id)
      }.to change { job.workflows.where(trigger_kind: "resume").count }.by(1)

      wf = job.workflows.where(trigger_kind: "resume").last
      first_run = wf.first_step.runs.first
      expect(first_run.parent_session_id).to eq("uuid-deadbeef")
      expect(response).to redirect_to(job_path(job))
      expect(flash[:notice]).to match(/Resume workflow enqueued/)
    end

    it "refuses when the source Run isn't failed/cancelled" do
      open_run = job.initial_run  # state=queued
      ClaudeSession.create!(resumable: open_run, session_id: "x", transcript_jsonl: "x")

      expect {
        post resume_job_path(job, source_run_id: open_run.id)
      }.not_to change { job.workflows.where(trigger_kind: "resume").count }
      expect(flash[:alert]).to match(/Only failed or cancelled/)
    end

    it "refuses when the source Run has no captured agent session" do
      expect {
        post resume_job_path(job, source_run_id: failed_run.id)
      }.not_to change { job.workflows.where(trigger_kind: "resume").count }
      expect(flash[:alert]).to match(/No agent session captured/)
      expect(flash[:alert]).not_to match(/Claude session|ClaudeSession/)
    end

    it "refuses when the source_run_id doesn't belong to this Job" do
      other_job = Factories.job(repository: repository, issue_number: 99)
      stranger = other_job.initial_run
      stranger.start!; stranger.fail!; stranger.save!
      ClaudeSession.create!(resumable: stranger, session_id: "y", transcript_jsonl: "y")

      post resume_job_path(job, source_run_id: stranger.id)
      expect(flash[:alert]).to match(/not found/)
    end

    it "404s for another user's job" do
      foreign_repo = Factories.repository(user: other)
      foreign_job = Factories.job(repository: foreign_repo, issue_number: 1)
      post resume_job_path(foreign_job, source_run_id: 1)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /jobs/:id/rebase" do
    before { sign_in_as(user) }

    it "instantiates a Rebase Workflow when the Job has a PR and no rebase is in flight" do
      job.update!(pr_number: 7, branch_name: "syrus/issue-42-1")

      expect {
        post rebase_job_path(job)
      }.to change { job.workflows.where(trigger_kind: "rebase").count }.by(1)
      expect(response).to redirect_to(job_path(job))
      expect(flash[:notice]).to match(/Rebase workflow enqueued/)
    end

    it "switches the job and instantiates Rebase with an explicitly selected configured agent" do
      user.update!(claude_oauth_token: "oat-test", codex_auth_mode: "api_key", codex_api_key: "sk-test")
      job.update!(pr_number: 7, branch_name: "syrus/issue-42-1", agent_provider: "claude")

      expect {
        post rebase_job_path(job), params: { agent_provider: "codex" }
      }.to change { job.workflows.where(trigger_kind: "rebase").count }.by(1)

      workflow = job.workflows.where(trigger_kind: "rebase").last
      expect(job.reload.agent_provider).to eq("codex")
      expect(workflow.agent_provider).to eq("codex")
      expect(workflow.first_step.runs.last.agent_provider).to eq("codex")
      expect(flash[:notice]).to match(/with Codex/)
    end

    it "rejects an explicitly selected rebase agent that is not configured" do
      user.update!(claude_oauth_token: "oat-test", codex_api_key: nil)
      job.update!(pr_number: 7, branch_name: "syrus/issue-42-1", agent_provider: "claude")

      expect {
        post rebase_job_path(job), params: { agent_provider: "codex" }
      }.not_to change { job.workflows.where(trigger_kind: "rebase").count }

      expect(job.reload.agent_provider).to eq("claude")
      expect(flash[:alert]).to match(/not configured/)
    end

    it "works on a closed (preempted) Job using external_pr_number" do
      job.update!(state: "closed", closure_reason: "preempted",
                  external_pr_number: 99, finished_at: Time.current)

      expect {
        post rebase_job_path(job)
      }.to change { job.workflows.where(trigger_kind: "rebase").count }.by(1)
    end

    it "refuses when the Job has no PR at all" do
      job  # force creation + initial Run before the assertion
      expect {
        post rebase_job_path(job)
      }.not_to change(Workflow, :count)
      expect(response).to redirect_to(job_path(job))
      expect(flash[:alert]).to match(/No PR/)
    end

    it "refuses when a rebase Workflow is already in flight" do
      job.update!(pr_number: 7, branch_name: "syrus/issue-42-1")
      Workflow.create!(job: job, trigger_kind: "rebase", state: "queued")

      expect {
        post rebase_job_path(job)
      }.not_to change { job.workflows.where(trigger_kind: "rebase").count }
      expect(flash[:alert]).to match(/already in progress/)
    end

    it "404s for another user's job" do
      foreign_repo = Factories.repository(user: other)
      foreign_job = Factories.job(repository: foreign_repo, issue_number: 1)
      foreign_job.update!(pr_number: 7)
      post rebase_job_path(foreign_job)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /jobs/:id/source/legacy" do
    it "does not route the retired source browser fallback" do
      expect {
        Rails.application.routes.recognize_path("/jobs/#{job.id}/source/legacy", method: :get)
      }.to raise_error(ActionController::RoutingError)
    end
  end

  describe "POST /jobs/:id/check_mergeability" do
    before { sign_in_as(user) }

    it "enqueues PollRebaseJob with bypass_cache: true when the Job has a PR" do
      job.update!(pr_number: 7)
      expect {
        post check_mergeability_job_path(job)
      }.to have_enqueued_job(PollRebaseJob).with(job.id, bypass_cache: true)
      expect(response).to redirect_to(job_path(job))
      expect(flash[:notice]).to match(/Checking mergeability/)
    end

    it "works on a preempted Job using external_pr_number" do
      job.update!(state: "closed", closure_reason: "preempted",
                  external_pr_number: 99, finished_at: Time.current)
      expect {
        post check_mergeability_job_path(job)
      }.to have_enqueued_job(PollRebaseJob).with(job.id, bypass_cache: true)
    end

    it "refuses when the Job has no PR" do
      expect {
        post check_mergeability_job_path(job)
      }.not_to have_enqueued_job(PollRebaseJob)
      expect(flash[:alert]).to match(/No PR/)
    end
  end

  describe "POST /jobs/:id/push_commits" do
    before { sign_in_as(user) }

    let(:failed_workflow) do
      Workflow.create!(job: job, trigger_kind: "initial",
                       state: "failed", started_at: 2.minutes.ago, finished_at: 1.minute.ago)
    end

    before { failed_workflow }  # ensure created before assertions

    it "enqueues PushPendingCommitsJob for a failed workflow with intact workspace" do
      expect {
        post push_commits_job_path(job, workflow_id: failed_workflow.id)
      }.to have_enqueued_job(PushPendingCommitsJob).with(failed_workflow.id)
      expect(response).to redirect_to(job_path(job))
      expect(flash[:notice]).to match(/Pushing commits/)
    end

    it "refuses when the workflow is not in a failed state" do
      failed_workflow.update_columns(state: "running", finished_at: nil)
      expect {
        post push_commits_job_path(job, workflow_id: failed_workflow.id)
      }.not_to have_enqueued_job(PushPendingCommitsJob)
      expect(flash[:alert]).to match(/not available/)
    end

    it "refuses when the workspace has already been cleaned up" do
      failed_workflow.update_columns(cleaned_up_at: Time.current)
      expect {
        post push_commits_job_path(job, workflow_id: failed_workflow.id)
      }.not_to have_enqueued_job(PushPendingCommitsJob)
      expect(flash[:alert]).to match(/not available/)
    end

    it "returns not found for a workflow_id that doesn't belong to this Job" do
      other_job  = Factories.job(repository: repository, issue_number: 99)
      other_wf   = Workflow.create!(job: other_job, trigger_kind: "initial",
                                    state: "failed", started_at: 1.minute.ago, finished_at: Time.current)
      expect {
        post push_commits_job_path(job, workflow_id: other_wf.id)
      }.not_to have_enqueued_job(PushPendingCommitsJob)
      expect(flash[:alert]).to match(/not found/)
    end

    it "404s for another user's job" do
      foreign_repo = Factories.repository(user: other)
      foreign_job  = Factories.job(repository: foreign_repo, issue_number: 1)
      post push_commits_job_path(foreign_job, workflow_id: failed_workflow.id)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "job pins" do
    context "signed in" do
      before { sign_in_as(user) }

      it "pins and unpins one of the current user's jobs" do
        SmartFolder.ensure_builtins!
        pinned_folder = SmartFolder.find_builtin_by_attention("pinned")
        pinned_url = root_url(smart_folder_id: pinned_folder.id)

        expect {
          post job_pin_path(job), headers: { "HTTP_REFERER" => pinned_url }
        }.to change { user.job_pins.where(job: job).count }.by(1)

        expect(response).to redirect_to(pinned_url)
        expect(flash[:notice]).to eq("Job pinned.")

        expect {
          delete job_pin_path(job), headers: { "HTTP_REFERER" => pinned_url }
        }.to change { user.job_pins.where(job: job).count }.by(-1)

        expect(response).to redirect_to(pinned_url)
        expect(flash[:notice]).to eq("Job unpinned.")
      end

      it "does not pin another user's job" do
        other_repo = Factories.repository(user: other, owner: "globex", name: "things")
        other_job = Factories.job(repository: other_repo, issue_number: 99)

        post job_pin_path(other_job)

        expect(response).to have_http_status(:not_found)
        expect(other.job_pins.where(job: other_job)).to be_empty
        expect(user.job_pins.where(job: other_job)).to be_empty
      end
    end
  end

  describe "GET /jobs/new" do
    it "requires authentication" do
      user  # ensure a user exists so auth redirects to login, not registration
      get new_job_path
      expect(response).to redirect_to(new_session_path)
    end

    context "signed in" do
      before { sign_in_as(user) }

      it "serves the React app shell" do
        get new_job_path

        expect(response).to be_successful
        expect(response.body).to include('id="syrus-spa-root"')
      end
    end
  end

  describe "legacy direct job endpoints" do
    it "does not route retired direct-job HTML endpoints" do
      expect {
        Rails.application.routes.recognize_path("/jobs/new/legacy", method: :get)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/jobs/legacy", method: :post)
      }.to raise_error(ActionController::RoutingError)
      expect {
        Rails.application.routes.recognize_path("/jobs", method: :post)
      }.to raise_error(ActionController::RoutingError)
    end
  end

  describe "job dependency controls" do
    before { sign_in_as(user) }

    it "adds and removes manual dependencies from the job page" do
      prerequisite = Job.create!(user: user, repository: repository, issue_number: 41)
      target = Job.create!(user: user, repository: repository, issue_number: 42)

      post dependencies_job_path(target), params: { dependency_target: "issue:#{repository.id}:41" }
      dependency = target.reload.dependencies.first

      expect(dependency.depends_on_job).to eq(prerequisite)
      expect(dependency.source).to eq("manual")
      expect(response).to redirect_to(job_path(target))

      delete dependency_job_path(target, dependency)
      expect(target.reload.dependencies).to be_empty
    end

    it "adds a selected job target as a manual dependency" do
      prerequisite = Job.create!(user: user, repository: repository, issue_number: 41)
      target = Job.create!(user: user, repository: repository, issue_number: 42)

      post dependencies_job_path(target), params: { dependency_target: "job:#{prerequisite.id}" }

      expect(target.reload.dependencies.first.depends_on_job).to eq(prerequisite)
    end

    it "does not resolve a selected issue target back to the current job" do
      target = Job.create!(user: user, repository: repository, issue_number: 41)

      post dependencies_job_path(target), params: { dependency_target: "issue:#{repository.id}:41" }

      expect(response).to redirect_to(job_path(target))
      expect(flash[:alert]).to eq("Dependency Job not found.")
      expect(target.reload.dependencies).to be_empty
    end

    it "lets admins override dependency gates" do
      prerequisite = Job.create!(user: user, repository: repository, issue_number: 41)
      target = Job.create!(user: user, repository: repository, issue_number: 42, issue_body: "Depends-on: #41")
      target.advance_after_triage!
      user.update!(admin: true)

      expect(target.runs).to be_empty

      expect {
        post override_dependencies_job_path(target)
      }.to have_enqueued_job(RunJob)

      expect(target.reload.dependencies_overridden_by_user).to eq(user)
      expect(target.runs.count).to eq(1)
      expect(prerequisite).to be_present
    end

  end

  describe "POST /jobs/:id/start" do
    before { sign_in_as(user) }

    it "starts a queued direct workflow without creating it at bug-report submit time" do
      direct = Job.create!(
        user: user,
        repository: repository,
        kind: "direct",
        issue_number: nil,
        issue_title: "Screenshot bug",
        issue_body: "Screenshot bug\n\nThe nav is sideways."
      )
      workflow = Workflows::Initial.instantiate(job: direct, agent_provider: direct.agent_provider)

      expect(direct.runs).to be_empty
      expect {
        post start_job_path(direct)
      }.to have_enqueued_job(RunJob).and change(Run, :count).by(1)

      expect(response).to redirect_to(job_path(direct, tab: "workflows"))
      expect(workflow.reload).to be_queued
      expect(direct.reload.runs.first.prompt).to include("Screenshot bug")
    end

  end
end
