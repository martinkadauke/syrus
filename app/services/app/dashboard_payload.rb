module App
  class DashboardPayload
    include Rails.application.routes.url_helpers

    SUBJECTS = %w[job epic workflow].freeze
    VIEWS = %w[list kanban].freeze
    DEFAULT_SUBJECT = "epic"
    DEFAULT_VIEW = "list"
    PER_PAGE = 25

    def self.call(user:, params:)
      new(user: user, params: params).call
    end

    def initialize(user:, params:)
      @user = user
      @params = params
    end

    def call
      persist_subject_preferences
      SmartFolder.ensure_builtins!

      {
        subject: subject,
        view: view,
        page: page,
        per_page: PER_PAGE,
        total: current_result.fetch(:total),
        total_pages: total_pages(current_result.fetch(:total)),
        counts: counts,
        preferences: preferences_json,
        smart_folders: smart_folders_json,
        active_smart_folder_id: active_smart_folder&.id,
        items: current_result.fetch(:items),
        paths: paths_json
      }
    end

    private

    attr_reader :user, :params

    def current_result
      @current_result ||= case subject
      when "job"
        jobs_result
      when "workflow"
        workflows_result
      else
        epics_result
      end
    end

    def subject
      @subject ||= normalize_subject(params[:subject]) ||
                   normalize_subject(params[:dashboard_subject]) ||
                   normalize_subject(user.dashboard_preferences["last_subject"]) ||
                   DEFAULT_SUBJECT
    end

    def view
      @view ||= params[:view].to_s.presence_in(VIEWS) ||
                user.dashboard_preferences["last_view"].to_s.presence_in(VIEWS) ||
                DEFAULT_VIEW
    end

    def page
      @page ||= [ Integer(params[:page], exception: false).to_i, 1 ].max
    end

    def active_repo_ids
      @active_repo_ids ||= user.repositories.active.pluck(:id)
    end

    def active_smart_folder
      @active_smart_folder ||= begin
        id = Integer(params[:smart_folder_id], exception: false)
        if id
          SmartFolder.for_subject(subject)
                     .where("user_id IS NULL OR user_id = ?", user.id)
                     .find_by(id: id)
        end
      end
    end

    def jobs_result
      scope = user.jobs.where(repository_id: active_repo_ids)
      filter = Jobs::Filter.from_params(params, smart_folder: active_smart_folder, user: user)
      scope = filter.apply(scope)
      total = scope.count
      scope = scope.with_latest_workflow_snapshot.preload(:repository, :tags)
      items = paginate(apply_sort(scope, :job)).map { |job| job_json(job) }

      { total: total, items: items }
    end

    def epics_result
      filter = Epics::Filter.from_params(params, smart_folder: active_smart_folder, user: user)
      scope = user.epics.where(repository_id: active_repo_ids).includes(:repository)
      scope = scope.where.not(state: Epic::ARCHIVED_STATE) unless filter.includes_archived_state?
      scope = filter.apply(scope)
      total = scope.count
      items = paginate(apply_sort(scope, :epic)).map { |epic| epic_json(epic) }

      { total: total, items: items }
    end

    def workflows_result
      scope = Workflow.joins(:job)
                      .where(jobs: { user_id: user.id, repository_id: active_repo_ids })
                      .includes(:steps, job: :repository)
      filter = Workflows::Filter.from_params(params, smart_folder: active_smart_folder, user: user)
      scope = filter.apply(scope)
      total = scope.count
      items = paginate(apply_sort(scope, :workflow)).map { |workflow| workflow_json(workflow) }

      { total: total, items: items }
    end

    def counts
      @counts ||= {
        jobs: user.jobs.where(repository_id: active_repo_ids).count,
        epics: user.epics.where(repository_id: active_repo_ids).where.not(state: Epic::ARCHIVED_STATE).count,
        workflows: Workflow.joins(:job).where(jobs: { user_id: user.id, repository_id: active_repo_ids }).count
      }
    end

    def apply_sort(scope, subject_name)
      sort = user.dashboard_sort(subject_name)
      column = sort_value(sort, "column")
      direction = sort_value(sort, "direction") == "asc" ? :asc : :desc

      case [ subject_name.to_s, column ]
      when [ "job", "title" ]
        scope.reorder(Job.arel_table[:issue_title].public_send(direction), Job.arel_table[:id].public_send(direction))
      when [ "job", "state" ]
        scope.reorder(Job.arel_table[:state].public_send(direction), Job.arel_table[:id].public_send(direction))
      when [ "job", "repository" ]
        scope.joins(:repository).reorder(Repository.arel_table[:name].public_send(direction), Job.arel_table[:id].public_send(direction))
      when [ "job", "started_at" ]
        scope.reorder(Job.arel_table[:started_at].public_send(direction), Job.arel_table[:id].public_send(direction))
      when [ "epic", "title" ]
        scope.reorder(Epic.arel_table[:title].public_send(direction), Epic.arel_table[:id].public_send(direction))
      when [ "epic", "state" ]
        scope.reorder(Epic.arel_table[:state].public_send(direction), Epic.arel_table[:id].public_send(direction))
      when [ "epic", "repository" ]
        scope.joins(:repository).reorder(Repository.arel_table[:name].public_send(direction), Epic.arel_table[:id].public_send(direction))
      when [ "workflow", "title" ]
        scope.reorder(Workflow.arel_table[:id].public_send(direction))
      when [ "workflow", "state" ]
        scope.reorder(Workflow.arel_table[:state].public_send(direction), Workflow.arel_table[:id].public_send(direction))
      when [ "workflow", "finished_at" ]
        scope.reorder(Workflow.arel_table[:finished_at].public_send(direction), Workflow.arel_table[:id].public_send(direction))
      else
        default_sort(scope, subject_name, direction)
      end
    end

    def default_sort(scope, subject_name, direction)
      case subject_name.to_s
      when "epic"
        scope.reorder(Epic.arel_table[:updated_at].public_send(direction), Epic.arel_table[:id].public_send(direction))
      when "workflow"
        scope.reorder(Workflow.arel_table[:started_at].public_send(direction), Workflow.arel_table[:id].public_send(direction))
      else
        scope.reorder(Job.arel_table[:created_at].public_send(direction), Job.arel_table[:id].public_send(direction))
      end
    end

    def paginate(scope)
      scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE)
    end

    def total_pages(total)
      return 1 if total.to_i.zero?

      (total.to_f / PER_PAGE).ceil
    end

    def job_json(job)
      {
        type: "job",
        id: job.id,
        kind: job.kind,
        title: job.issue_title.presence || job.kind.humanize,
        state: job.state,
        summary_state: summary_state(job),
        validity: job.validity,
        priority: job.priority,
        issue_number: job.issue_number,
        branch_name: job.branch_name,
        pr_number: job.pr_number || job.external_pr_number,
        latest_workflow_state: job.latest_workflow_state,
        created_at: job.created_at&.iso8601,
        updated_at: job.updated_at&.iso8601,
        started_at: job.started_at&.iso8601,
        finished_at: job.finished_at&.iso8601,
        repository: repository_json(job.repository),
        tags: job.tags.map { |tag| tag_json(tag) },
        paths: {
          job_path: job_path(job),
          source_path: source_job_path(job)
        }
      }
    end

    def epic_json(epic)
      {
        type: "epic",
        id: epic.id,
        number: epic.number,
        display_number: epic.display_number,
        title: epic.title,
        state: epic.state,
        auto_approve_mode: epic.auto_approve_mode,
        created_at: epic.created_at&.iso8601,
        updated_at: epic.updated_at&.iso8601,
        done_at: epic.done_at&.iso8601,
        repository: repository_json(epic.repository),
        paths: {
          epic_path: epic_path(epic),
          edit_epic_path: edit_epic_path(epic)
        }
      }
    end

    def workflow_json(workflow)
      job = workflow.job
      {
        type: "workflow",
        id: workflow.id,
        state: workflow.state,
        trigger_kind: workflow.trigger_kind,
        agent_provider: workflow.agent_provider,
        created_at: workflow.created_at&.iso8601,
        updated_at: workflow.updated_at&.iso8601,
        started_at: workflow.started_at&.iso8601,
        finished_at: workflow.finished_at&.iso8601,
        steps_count: workflow.steps.size,
        job: {
          id: job.id,
          title: job.issue_title.presence || job.kind.humanize,
          state: job.state,
          repository: repository_json(job.repository),
          path: job_path(job)
        }
      }
    end

    def smart_folders_json
      folders = SmartFolder.for_subject(subject)
                           .where("user_id IS NULL OR user_id = ?", user.id)
                           .order(Arel.sql("CASE WHEN user_id IS NULL THEN 0 ELSE 1 END"), :position, :id)

      folders.map do |folder|
        {
          id: folder.id,
          name: folder.name,
          kind: folder.kind,
          subject_type: folder.subject_type,
          active: active_smart_folder&.id == folder.id,
          path: dashboard_path_for(subject, smart_folder_id: folder.id)
        }
      end
    end

    def preferences_json
      table = subject.pluralize
      {
        sort: user.dashboard_sort(subject),
        visible_columns: user.dashboard_visible_columns(subject),
        kanban_lanes: user.dashboard_visible_kanban_lanes(subject),
        raw: user.dashboard_preferences.fetch(table)
      }
    end

    def paths_json
      {
        dashboard_path: dashboard_path_for(subject),
        dashboard_jobs_path: dashboard_jobs_path,
        dashboard_epics_path: dashboard_epics_path,
        dashboard_workflows_path: dashboard_workflows_path,
        app_dashboard_path: "/api/v1/app/dashboard"
      }
    end

    def dashboard_path_for(target_subject, extra = {})
      case target_subject.to_s
      when "epic"
        dashboard_epics_path({ view: view }.merge(extra))
      when "workflow"
        dashboard_workflows_path({ view: view }.merge(extra))
      else
        dashboard_jobs_path({ view: view }.merge(extra))
      end
    end

    def repository_json(repository)
      {
        id: repository.id,
        slug: repository.slug
      }
    end

    def tag_json(tag)
      {
        id: tag.id,
        name: tag.name,
        color: tag.color
      }
    end

    def summary_state(job)
      return "preempted" if job.closure_reason == "preempted"
      return "preempted" if job.closure_reason&.start_with?("external_pr_")

      job.state
    end

    def persist_subject_preferences
      return unless params.key?(:subject) || params.key?(:view)

      user.update_dashboard_preferences!(subject: subject, view: view)
    end

    def normalize_subject(value)
      normalized = value.to_s.singularize
      normalized.presence_in(SUBJECTS)
    end

    def sort_value(sort, key)
      sort[key] || sort[key.to_sym]
    end
  end
end
