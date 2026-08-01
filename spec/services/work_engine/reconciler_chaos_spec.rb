require "rails_helper"

RSpec.describe "Work engine reconciler chaos simulation" do
  include ActiveJob::TestHelper

  CaseExpectation = Data.define(
    :label,
    :target,
    :expected_issue,
    :expected_action,
    :forbidden_issues,
    :forbidden_actions,
    :trace
  ) do
    def initialize(label:, target:, expected_issue: nil, expected_action: nil, forbidden_issues: [], forbidden_actions: [], trace: [])
      super(
        label: label,
        target: target,
        expected_issue: expected_issue&.to_s,
        expected_action: expected_action&.to_s,
        forbidden_issues: forbidden_issues.map(&:to_s),
        forbidden_actions: forbidden_actions.map(&:to_s),
        trace: trace
      )
    end
  end

  class ReconcilerChaosSimulation
    attr_reader :seed, :live_worker_hosts

    SCENARIOS = %i[
      queued_without_queue_claim
      queued_failed_solid_queue_execution
      queued_dead_resume_queue
      queued_with_healthy_queue_job_beside_dead_resume_job
      inline_successor_owned_by_live_root_job
      stale_auto_retry_workflow_with_queued_run
      stale_running_run_without_worker_evidence
      fresh_running_run
      missing_local_workspace
      missing_remote_live_worker_workspace
      stale_main_broken_artifact_after_recovery
      active_main_health_start_block
      recovered_main_health_start_block
      running_workflow_without_active_descendants
      terminal_workflow_with_active_descendants
    ].freeze

    def initialize(seed:, spec_context:)
      @seed = seed
      @random = Random.new(seed)
      @spec_context = spec_context
      @case_number = 0
      @live_worker_hosts = Set.new
    end

    def next_case
      @case_number += 1
      @trace = [ "seed=#{seed}", "case=#{@case_number}" ]
      @live_worker_hosts.clear
      clear_solid_queue

      scenario = SCENARIOS.sample(random: @random)
      @trace << "scenario=#{scenario}"
      send(scenario)
    end

    def live_worker?(hostname)
      live_worker_hosts.include?(hostname)
    end

    private

    attr_reader :random, :spec_context, :case_number, :trace

    def clear_solid_queue
      spec_context.clear_solid_queue_test_tables!
      trace << "solid_queue=cleared"
    end

    def graph
      reset_shared_repository!
      job = Factories.job(
        user: shared_user,
        repository: shared_repository,
        issue_number: case_number,
        agent_provider: random_provider
      )
      workflow = job.latest_workflow
      step = workflow.first_step
      run = step.runs.first
      trace << "job=#{job.id} workflow=#{workflow.id} step=#{step.id} run=#{run.id}"
      [ job, workflow, step, run ]
    end

    def shared_user
      @shared_user ||= Factories.user
    end

    def shared_repository
      @shared_repository ||= Factories.repository(user: shared_user)
    end

    def reset_shared_repository!
      shared_repository.update!(
        main_branch_health_enabled: true,
        ci_health: "healthy",
        grader_health: "healthy",
        landing_paused: false
      )
    end

    def random_provider
      random.rand(2).zero? ? "claude" : "codex"
    end

    def old_active_age
      (ReapStaleRunsJob::ORPHAN_RUN_GRACE_PERIOD + random.rand(1..6).minutes)
    end

    def stale_heartbeat_age
      Run::STALE_HEARTBEAT_THRESHOLD + random.rand(1..10).minutes
    end

    def queued_run!(workflow, step, run, age: old_active_age)
      workflow.update_columns(state: "running", started_at: age.ago)
      step.update_columns(state: "queued", created_at: age.ago, updated_at: age.ago)
      run.update_columns(state: "queued", created_at: age.ago, updated_at: age.ago)
      trace << "run=#{run.id}:queued age=#{age.inspect}"
    end

    def running_run!(workflow, step, run, heartbeat_age:)
      workflow.update_columns(state: "running", started_at: heartbeat_age.ago)
      step.update_columns(state: "running", started_at: heartbeat_age.ago)
      run.update_columns(
        state: "running",
        started_at: heartbeat_age.ago,
        last_heartbeat_at: heartbeat_age.ago
      )
      trace << "run=#{run.id}:running heartbeat_age=#{heartbeat_age.inspect}"
    end

    def finished_run!(workflow, step, run)
      workflow.update_columns(state: "running", started_at: 6.minutes.ago)
      step.update_columns(state: "queued", updated_at: 5.minutes.ago)
      run.update_columns(state: "succeeded", finished_at: 5.minutes.ago)
      trace << "run=#{run.id}:succeeded"
    end

    def remove_first_run!(workflow, run)
      run.destroy!
      workflow.update_columns(state: "queued", created_at: 5.minutes.ago, updated_at: 5.minutes.ago)
      trace << "workflow=#{workflow.id}:queued_without_first_run"
    end

    def solid_queue_run_job(run, ready: false, claimed: false, failed: false, queue_name: "runs", worker_host: "worker-live", live_process: true)
      created_at = 15.minutes.ago
      queue_job = SolidQueue::Job.create!(
        class_name: "RunJob",
        queue_name: queue_name,
        priority: 10,
        arguments: { "arguments" => [ run.id ] },
        created_at: created_at,
        updated_at: created_at
      )
      SolidQueue::ReadyExecution.create!(job: queue_job, priority: 10, queue_name: queue_name, created_at: created_at) if ready
      if claimed
        process = SolidQueue::Process.create!(
          hostname: worker_host,
          kind: "worker",
          last_heartbeat_at: live_process ? 10.seconds.ago : 20.minutes.ago,
          metadata: {},
          name: "#{worker_host}:#{queue_job.id}",
          pid: 1000 + queue_job.id,
          created_at: created_at
        )
        SolidQueue::ClaimedExecution.create!(job: queue_job, process_id: process.id, created_at: created_at)
      end
      SolidQueue::FailedExecution.create!(job: queue_job, error: "chaos failed execution", created_at: 1.minute.ago) if failed
      trace << "sq_job=#{queue_job.id} run=#{run.id} queue=#{queue_name} ready=#{ready} claimed=#{claimed} failed=#{failed}"
      queue_job
    end

    def missing_workspace!(workflow)
      matcher = spec_context.receive(:directory?)
        .with(WorkflowWorkspace.path_for(workflow))
        .and_return(false)
      spec_context.allow(File).to(matcher)
      trace << "workspace=#{workflow.id}:missing"
    end

    def queued_without_queue_claim
      _job, workflow, step, run = graph
      queued_run!(workflow, step, run)

      expectation(
        "queued run with no queue claim",
        target: { run_id: run.id },
        expected_issue: :queued_run_without_queue_claim,
        expected_action: :reenqueue_run
      )
    end

    def queued_failed_solid_queue_execution
      _job, workflow, step, run = graph
      queued_run!(workflow, step, run)
      solid_queue_run_job(run, failed: true)

      expectation(
        "queued run with failed Solid Queue execution",
        target: { run_id: run.id },
        expected_issue: :queued_run_solid_queue_failed_execution,
        expected_action: :reenqueue_run
      )
    end

    def queued_dead_resume_queue
      _job, workflow, step, run = graph
      worker_host = "chaos-dead-worker-#{case_number}"
      queued_run!(workflow, step, run)
      workflow.update_columns(worker_hostname: worker_host)
      solid_queue_run_job(run, ready: true, queue_name: "resume-#{worker_host}")

      expectation(
        "queued run on dead resume queue",
        target: { run_id: run.id },
        expected_issue: :queued_run_on_dead_resume_queue,
        expected_action: :reenqueue_run
      )
    end

    def queued_with_healthy_queue_job_beside_dead_resume_job
      _job, workflow, step, run = graph
      worker_host = "chaos-dead-worker-#{case_number}"
      queued_run!(workflow, step, run)
      workflow.update_columns(worker_hostname: worker_host)
      solid_queue_run_job(run, ready: true, queue_name: "resume-#{worker_host}")
      solid_queue_run_job(run, ready: true, queue_name: "runs")

      expectation(
        "queued run with healthy queue job beside dead resume job",
        target: { run_id: run.id },
        forbidden_issues: %i[queued_run_on_dead_resume_queue queued_run_solid_queue_failed_execution queued_run_without_queue_claim],
        forbidden_actions: %i[reenqueue_run]
      )
    end

    def inline_successor_owned_by_live_root_job
      job, workflow, step, root_run = graph
      finished_run!(workflow, step, root_run)
      successor = step.runs.create!(
        job: job,
        user: job.user,
        trigger_kind: workflow.trigger_kind,
        agent_provider: workflow.agent_provider,
        state: "queued",
        created_at: 5.minutes.ago,
        updated_at: 5.minutes.ago
      )
      solid_queue_run_job(root_run, claimed: true, worker_host: "chaos-live-worker-#{case_number}", live_process: true)
      trace << "successor_run=#{successor.id}:queued_inline"

      expectation(
        "queued inline successor owned by a live root RunJob",
        target: { workflow_id: workflow.id },
        forbidden_issues: %i[queued_run_without_queue_claim queued_run_stale_queue_claim],
        forbidden_actions: %i[reenqueue_run]
      )
    end

    def stale_auto_retry_workflow_with_queued_run
      job, source, step, run = graph
      fail_run!(source, step, run)
      job.update!(state: "implemented")
      successful = Workflows::Retry.instantiate(job: job, agent_provider: job.agent_provider)
      successful.update_columns(
        state: "succeeded",
        created_at: 4.minutes.ago,
        started_at: 4.minutes.ago,
        finished_at: 3.minutes.ago
      )
      attempt = AutoRetryAttempt.create!(
        job: job,
        workflow: source,
        run: run,
        agent_provider: job.agent_provider,
        failure_classification: "worker_died",
        retry_kind: "retry_workflow",
        attempt_number: 1,
        scheduled_at: 2.minutes.ago,
        performed_at: 2.minutes.ago
      )
      stale = Workflows::Retry.instantiate(
        job: job,
        artifacts: { "auto_retry_attempt_id" => attempt.id },
        agent_provider: job.agent_provider
      )
      stale.update_columns(created_at: 2.minutes.ago, updated_at: 2.minutes.ago)
      StepDispatcher.start_workflow(stale)
      stale_run = stale.first_step.runs.first
      stale_run.update_columns(created_at: old_active_age.ago, updated_at: old_active_age.ago)
      trace << "workflow=#{stale.id}:stale_auto_retry run=#{stale_run.id}:old_queued"

      expectation(
        "stale auto-retry workflow with queued run",
        target: { workflow_id: stale.id },
        expected_issue: :stale_auto_retry_workflow,
        expected_action: :cancel_stale_auto_retry_workflow,
        forbidden_issues: %i[queued_run_without_queue_claim],
        forbidden_actions: %i[reenqueue_run]
      )
    end

    def stale_running_run_without_worker_evidence
      _job, workflow, step, run = graph
      running_run!(workflow, step, run, heartbeat_age: stale_heartbeat_age)

      expectation(
        "stale running run without worker evidence",
        target: { run_id: run.id },
        expected_issue: :running_run_without_live_worker_evidence,
        expected_action: :mark_worker_died_and_retry_failed_step
      )
    end

    def fresh_running_run
      _job, workflow, step, run = graph
      running_run!(workflow, step, run, heartbeat_age: random.rand(10..50).seconds)

      expectation(
        "fresh running run",
        target: { run_id: run.id },
        forbidden_issues: %i[running_run_without_live_worker_evidence],
        forbidden_actions: %i[mark_worker_died mark_worker_died_and_retry_failed_step mark_worker_died_and_retry_workflow]
      )
    end

    def missing_local_workspace
      _job, workflow, step, run = graph
      running_run!(workflow, step, run, heartbeat_age: random.rand(10..50).seconds)
      missing_workspace!(workflow)

      expectation(
        "missing local workspace",
        target: { workflow_id: workflow.id },
        expected_issue: :workspace_missing,
        expected_action: :operator_review_missing_workspace
      )
    end

    def missing_remote_live_worker_workspace
      _job, workflow, step, run = graph
      worker_host = "chaos-remote-live-worker-#{case_number}"
      live_worker_hosts << worker_host
      running_run!(workflow, step, run, heartbeat_age: random.rand(10..50).seconds)
      workflow.update_columns(worker_hostname: worker_host)
      missing_workspace!(workflow)

      expectation(
        "missing workspace on another live worker",
        target: { workflow_id: workflow.id },
        forbidden_issues: %i[workspace_missing],
        forbidden_actions: %i[operator_review_missing_workspace]
      )
    end

    def stale_main_broken_artifact_after_recovery
      job, workflow, step, run = graph
      fail_run!(workflow, step, run)
      job.repository.update!(main_branch_health_enabled: true, ci_health: "healthy", grader_health: "healthy", landing_paused: false)
      workflow.update!(artifacts: { "main_broken" => true })
      trace << "main_health=recovered stale_artifact=true"

      expectation(
        "stale main-broken artifact after recovery",
        target: { workflow_id: workflow.id },
        forbidden_issues: %i[main_branch_broken main_health_start_block],
        forbidden_actions: %i[wait_for_main_recovery wait_for_main_health]
      )
    end

    def active_main_health_start_block
      job, workflow, _step, run = graph
      remove_first_run!(workflow, run)
      job.repository.update!(main_branch_health_enabled: true, ci_health: "broken", grader_health: "broken", landing_paused: true)
      workflow.update!(
        artifacts: {
          "start_blocked_reason" => StepDispatcher::MAIN_HEALTH_BLOCK_REASON,
          "start_blocked_next_check_at" => 5.minutes.from_now.iso8601
        }
      )
      trace << "main_health=broken"

      expectation(
        "active main-health start block",
        target: { workflow_id: workflow.id },
        expected_issue: :main_health_start_block,
        expected_action: :wait_for_main_health
      )
    end

    def recovered_main_health_start_block
      job, workflow, _step, run = graph
      remove_first_run!(workflow, run)
      job.repository.update!(main_branch_health_enabled: true, ci_health: "healthy", grader_health: "healthy", landing_paused: false)
      workflow.update!(
        artifacts: {
          "start_blocked_reason" => StepDispatcher::MAIN_HEALTH_BLOCK_REASON,
          "start_blocked_next_check_at" => 5.minutes.from_now.iso8601
        }
      )
      trace << "main_health=recovered"

      expectation(
        "recovered main-health start block",
        target: { workflow_id: workflow.id },
        expected_issue: :queued_workflow_without_first_run,
        expected_action: :start_workflow,
        forbidden_issues: %i[main_health_start_block],
        forbidden_actions: %i[wait_for_main_health]
      )
    end

    def running_workflow_without_active_descendants
      _job, workflow, _step, run = graph
      workflow.update_columns(state: "running", started_at: 6.minutes.ago)
      workflow.steps.update_all(state: "succeeded", finished_at: 4.minutes.ago)
      run.update_columns(state: "succeeded", finished_at: 4.minutes.ago)
      trace << "workflow=#{workflow.id}:running_without_active_descendants"

      expectation(
        "running workflow without active descendants",
        target: { workflow_id: workflow.id },
        expected_issue: :running_workflow_without_active_descendants,
        expected_action: :finish_workflow_from_terminal_descendants
      )
    end

    def terminal_workflow_with_active_descendants
      _job, workflow, step, run = graph
      workflow.update_columns(state: "succeeded", finished_at: 5.minutes.ago, cleaned_up_at: nil)
      step.update_columns(state: "running", started_at: 6.minutes.ago)
      run.update_columns(state: "running", started_at: 6.minutes.ago, last_heartbeat_at: 30.seconds.ago)
      trace << "workflow=#{workflow.id}:terminal_with_active_descendants"

      expectation(
        "terminal workflow with active descendants",
        target: { workflow_id: workflow.id },
        expected_issue: :cleanup_blocked_by_active_descendants,
        expected_action: :operator_review_active_descendants
      )
    end

    def fail_run!(workflow, step, run)
      workflow.update_columns(state: "failed", finished_at: 5.minutes.ago, cleaned_up_at: nil)
      step.update_columns(kind: "grader", state: "failed", finished_at: 5.minutes.ago)
      run.update_columns(state: "failed", finished_at: 5.minutes.ago)
      RunFailureClassification.create!(
        run: run,
        classification: "timeout",
        retryable: true,
        confidence: 0.9,
        reason: "chaos retryable failure",
        classified_at: 5.minutes.ago
      )
      trace << "run=#{run.id}:failed"
    end

    def expectation(label, target:, expected_issue: nil, expected_action: nil, forbidden_issues: [], forbidden_actions: [])
      CaseExpectation.new(
        label: label,
        target: target,
        expected_issue: expected_issue,
        expected_action: expected_action,
        forbidden_issues: forbidden_issues,
        forbidden_actions: forbidden_actions,
        trace: trace.dup
      )
    end
  end

  around do |example|
    clear_enqueued_jobs
    clear_performed_jobs
    example.run
    clear_enqueued_jobs
    clear_performed_jobs
  end

  before do
    ensure_solid_queue_test_tables!
    clear_solid_queue_test_tables!
    allow(ProviderCircuitBreaker).to receive(:open_circuits).and_return([])
    allow(InstanceVersion).to receive(:worst_data_root).and_return(nil)
    allow(File).to receive(:directory?).and_return(true)
  end

  after do
    clear_solid_queue_test_tables! if ActiveRecord::Base.connection.table_exists?(:solid_queue_jobs)
  end

  def chaos_case_count
    Integer(ENV.fetch("WORK_ENGINE_CHAOS_CASES", "5"))
  end

  def issue_kinds(result)
    result.issues.map(&:kind)
  end

  def plan_actions(result)
    result.repair_plans.map(&:action)
  end

  def assert_chaos_case!(expectation)
    result = WorkEngine::Reconciler.call(source: "reconciler_chaos_spec", **expectation.target)
    repeat = WorkEngine::Reconciler.call(source: "reconciler_chaos_spec_repeat", **expectation.target)
    trace = expectation.trace.join("\n")

    aggregate_failures "#{expectation.label}\n#{trace}" do
      if expectation.expected_issue
        expect(issue_kinds(result)).to include(expectation.expected_issue), "expected issue #{expectation.expected_issue}; got #{issue_kinds(result).inspect}\n#{trace}"
      end

      if expectation.expected_action
        expect(plan_actions(result)).to include(expectation.expected_action), "expected action #{expectation.expected_action}; got #{plan_actions(result).inspect}\n#{trace}"
      end

      expectation.forbidden_issues.each do |kind|
        expect(issue_kinds(result)).not_to include(kind), "forbidden issue #{kind}; got #{issue_kinds(result).inspect}\n#{trace}"
      end

      expectation.forbidden_actions.each do |action|
        expect(plan_actions(result)).not_to include(action), "forbidden action #{action}; got #{plan_actions(result).inspect}\n#{trace}"
      end

      expect(issue_kinds(repeat)).to eq(issue_kinds(result)), "reconciler issue set was not stable across repeated reads\n#{trace}"
      expect(plan_actions(repeat)).to eq(plan_actions(result)), "reconciler plan set was not stable across repeated reads\n#{trace}"
      expect(result.repair_plans.map { |plan| [ plan.action, plan.target_type, plan.target_id ] })
        .to eq(result.repair_plans.map { |plan| [ plan.action, plan.target_type, plan.target_id ] }.uniq),
          "duplicate repair plans emitted\n#{trace}"

      result.repair_plans.each do |plan|
        issue = result.issues.find { |candidate| candidate.kind == plan.issue_kind }
        expect(issue).to be_present, "plan #{plan.action} has no matching issue\n#{trace}"
        expect(plan.auto_executable).to be(false) unless issue&.safe_to_auto_repair
      end
    end
  end

  it "reconciles seeded random worker, queue, workspace, and main-health states without slow waits" do
    seed = Integer(ENV.fetch("WORK_ENGINE_CHAOS_SEED", Random.new_seed))
    simulation = ReconcilerChaosSimulation.new(seed: seed, spec_context: self)
    allow(InstanceVersion).to receive(:worker_live?) { |hostname| simulation.live_worker?(hostname) }

    chaos_case_count.times do
      expectation = simulation.next_case
      assert_chaos_case!(expectation)
    end
  end
end
