module Admin
  class ReconcilerActivityPayload
    PER_PAGE = 50
    MAX_PER_PAGE = 100

    def initialize(params: {})
      @params = params
    end

    def as_json(*)
      rows = relation.offset((page - 1) * per_page).limit(per_page).to_a
      {
        events: rows.map { |event| event_json(event) },
        pagination: {
          page: page,
          per_page: per_page,
          total: total,
          total_pages: total_pages,
          first_item: rows.empty? ? 0 : ((page - 1) * per_page) + 1,
          last_item: rows.empty? ? 0 : ((page - 1) * per_page) + rows.length,
          previous_path: page > 1 ? path_for(page - 1) : nil,
          next_path: page < total_pages ? path_for(page + 1) : nil
        },
        filters: {
          event_type: event_type,
          job_id: job_id,
          workflow_id: workflow_id,
          run_id: run_id
        },
        event_types: WorkEngineReconcilerActivityEvent::EVENT_TYPES
      }
    end

    private

    attr_reader :params

    def relation
      @relation ||= begin
        scope = WorkEngineReconcilerActivityEvent.includes(:job, :workflow, :run).recent_first
        scope = scope.where(event_type: event_type) if event_type.present?
        scope = scope.where(job_id: job_id) if job_id.present?
        scope = scope.where(workflow_id: workflow_id) if workflow_id.present?
        scope = scope.where(run_id: run_id) if run_id.present?
        scope
      end
    end

    def total
      @total ||= relation.count
    end

    def total_pages
      [ (total.to_f / per_page).ceil, 1 ].max
    end

    def page
      parsed = params[:page].to_i
      parsed.positive? ? parsed : 1
    end

    def per_page
      parsed = params[:per_page].to_i
      return PER_PAGE unless parsed.positive?

      [ parsed, MAX_PER_PAGE ].min
    end

    def event_type
      value = params[:event_type].to_s
      WorkEngineReconcilerActivityEvent::EVENT_TYPES.include?(value) ? value : nil
    end

    def job_id
      positive_int(params[:job_id])
    end

    def workflow_id
      positive_int(params[:workflow_id])
    end

    def run_id
      positive_int(params[:run_id])
    end

    def positive_int(value)
      parsed = value.to_i
      parsed.positive? ? parsed : nil
    end

    def event_json(event)
      {
        id: event.id,
        event_type: event.event_type,
        severity: event.severity,
        source: event.source,
        message: event.message,
        issue_kind: event.issue_kind,
        repair_action: event.repair_action,
        repair_status: event.repair_status,
        occurred_at: event.occurred_at&.iso8601,
        details: event.details || {},
        job: event.job ? job_json(event.job) : nil,
        workflow: event.workflow ? workflow_json(event.workflow) : nil,
        run: event.run ? run_json(event.run) : nil
      }
    end

    def job_json(job)
      {
        id: job.id,
        slug: job.slug,
        title: job.issue_title,
        path: "/jobs/#{job.id}"
      }
    end

    def workflow_json(workflow)
      {
        id: workflow.id,
        slug: workflow.slug,
        trigger_kind: workflow.trigger_kind,
        state: workflow.state,
        path: "/jobs/#{workflow.job_id}?tab=workflows#workflow-#{workflow.id}"
      }
    end

    def run_json(run)
      {
        id: run.id,
        state: run.state,
        path: "/admin/runs/#{run.id}/transcript"
      }
    end

    def path_for(target_page)
      raw_params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      query = raw_params.slice("event_type", "job_id", "workflow_id", "run_id", "per_page").merge("page" => target_page).compact_blank
      "/admin/reconciler_activity#{query.present? ? "?#{query.to_query}" : ""}"
    end
  end
end
