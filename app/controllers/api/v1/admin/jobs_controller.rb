module Api
  module V1
    module Admin
      # Single-shot Job state dump — collapses the "write a Rails
      # runner that joins Job + Workflows + Steps + Runs +
      # diagnostics + claude_session" investigation pattern into
      # one HTTP call.
      #
      # GET /api/v1/admin/jobs/:id → JSON
      class JobsController < BaseController
        def show
          job = Job.includes(workflows: { steps: :runs }).find(params[:id])
          render json: serialize(job)
        end

        private

        def serialize(job)
          {
            id: job.id,
            state: job.state,
            kind: job.kind,
            closure_reason: job.closure_reason,
            failure_count: job.failure_count,
            repository: { id: job.repository.id, slug: job.repository.slug, default_branch: job.repository.default_branch },
            user_email: job.user.email_address,
            issue_number: job.issue_number,
            issue_title: job.issue_title,
            branch_name: job.branch_name,
            pr_number: job.pr_number,
            external_pr_number: job.external_pr_number,
            pr_mergeable: job.pr_mergeable,
            pr_mergeable_checked_at: job.pr_mergeable_checked_at,
            scheduled_task_id: job.scheduled_task_id,
            started_at: job.started_at,
            finished_at: job.finished_at,
            workflows: job.workflows.order(:created_at).map { |wf| serialize_workflow(wf) }
          }
        end

        def serialize_workflow(wf)
          {
            id: wf.id,
            trigger_kind: wf.trigger_kind,
            state: wf.state,
            failure_count: wf.failure_count,
            artifacts: wf.artifacts,
            cleaned_up_at: wf.cleaned_up_at,
            retry_available: wf.retry_available?,
            started_at: wf.started_at,
            finished_at: wf.finished_at,
            steps: wf.steps.order(:position).map { |s| serialize_step(s) }
          }
        end

        def serialize_step(step)
          {
            id: step.id,
            kind: step.kind,
            position: step.position,
            state: step.state,
            started_at: step.started_at,
            finished_at: step.finished_at,
            runs: step.runs.order(:created_at).map { |r| serialize_run(r) }
          }
        end

        def serialize_run(run)
          {
            id: run.id,
            state: run.state,
            trigger_kind: run.trigger_kind,
            agent_outcome: run.agent_outcome,
            agent_turns: run.agent_turns,
            agent_pr_title: run.agent_pr_title,
            parent_session_id: run.parent_session_id,
            head_sha: run.head_sha,
            started_at: run.started_at,
            last_heartbeat_at: run.last_heartbeat_at,
            finished_at: run.finished_at,
            agent_diff_present: run.agent_diff.present?,
            agent_diff_bytes: run.agent_diff&.bytesize || 0,
            job_log_count: run.job_logs.size,
            claude_session: run.claude_session && {
              session_id: run.claude_session.session_id,
              transcript_bytes: run.claude_session.transcript_jsonl.bytesize,
              transcript_lines: run.claude_session.transcript_jsonl.count("\n")
            },
            run_diagnostic: run.run_diagnostic && {
              error_class: run.run_diagnostic.error_class,
              error_message: run.run_diagnostic.error_message,
              created_at: run.run_diagnostic.created_at
            }
          }
        end
      end
    end
  end
end
