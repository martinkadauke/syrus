module App
  class DashboardPayload
    include Rails.application.routes.url_helpers
    include OwnershipScoping
    include KanbanLanes

    SUBJECTS = %w[job epic workflow].freeze
    VIEWS = %w[list kanban].freeze
    SECTIONS = %w[full chrome rows].freeze
    DEFAULT_SUBJECT = "epic"
    DEFAULT_VIEW = "list"
    FOLDER_PREFERENCE_DEFAULTS = {
      [ "epic", "null" ] => { "view" => "kanban" },
      [ "epic", "epics_mine" ] => { "view" => "kanban" },
      [ "epic", "epics_claimable" ] => { "view" => "list" },
      [ "job", "landing_queue" ] => { "sort_column" => "landing_queue_position", "sort_direction" => "asc" }
    }.freeze
    PER_PAGE = 25
    KANBAN_LIMIT_OPTIONS = [ 10, 25, 50, 100 ].freeze
    KANBAN_PER_PAGE = 100
    JOB_KANBAN_LANES = [
      { key: "blocked", title: "Blocked" },
      { key: "queued", title: "Queued" },
      { key: "running", title: "Running" },
      { key: "succeeded", title: "Succeeded" },
      { key: "landing", title: "Landing" },
      { key: "failed", title: "Failed" }
    ].freeze
    WORKFLOW_DONE_STATES = %w[succeeded failed cancelled].freeze
    COLUMN_LABELS = {
      "epics" => {
        "epic" => "Epic",
        "state" => "State",
        "owner" => "Owner",
        "repository" => "Repository",
        "updated" => "Updated",
        "created_at" => "Created at",
        "updated_at" => "Updated at",
        "done_at" => "Done at",
        "archived_at" => "Archived at"
      },
      "jobs" => {
        "checkbox" => "Checkbox",
        "issue" => "Issue",
        "state" => "State",
        "landing_queue_position" => "Queue",
        "landing_queue_blocked_reason" => "Blocked reason",
        "repository" => "Repository",
        "owner" => "Owner",
        "latest" => "Latest",
        "workflows_count" => "Workflows count",
        "started" => "Started",
        "created_at" => "Created at",
        "updated_at" => "Updated at",
        "started_at" => "Started at",
        "finished_at" => "Finished at",
        "approved_at" => "Approved at",
        "dependencies_overridden_at" => "Dependencies overridden at",
        "last_feedback_addressed_at" => "Last feedback addressed at",
        "last_seen_comment_at" => "Last seen comment at",
        "pr_mergeable_checked_at" => "PR mergeable checked at"
      },
      "workflows" => {
        "workflow" => "Workflow",
        "job" => "Job",
        "trigger" => "Trigger",
        "state" => "State",
        "started" => "Started",
        "finished" => "Finished",
        "agent" => "Agent",
        "created_at" => "Created at",
        "updated_at" => "Updated at",
        "started_at" => "Started at",
        "finished_at" => "Finished at",
        "cleaned_up_at" => "Cleaned up at"
      }
    }.freeze

    class InvalidScope < StandardError; end

    def self.call(user:, params:)
      new(user: user, params: params).call
    end

    def initialize(user:, params:)
      @user = user
      @params = params
    end

    def call
      PerformanceLogging.phase("dashboard_payload", subject: subject, view: view, ownership_scope: ownership_scope) do
        SmartFolder.ensure_builtins_for_subject!(subject)

        case section
        when "chrome"
          chrome_payload
        when "rows"
          rows_payload
        else
          chrome_payload.merge(rows_payload)
        end
      end
    end

    def chrome_payload
      {
        subject: subject,
        view: view,
        page: page,
        per_page: PER_PAGE,
        counts: counts,
        ownership_scope: ownership_scope_json,
        preferences: preferences_json,
        controls: controls_json,
        ownership: ownership_json,
        filter: current_filter.to_h,
        landing_queue: landing_queue_chrome_json,
        broken_repositories: health_blocked_repositories_json,
        health_blocked_repositories: health_blocked_repositories_json,
        smart_folders: smart_folders_json,
        active_smart_folder_id: active_smart_folder&.id,
        setup: ::App::SetupStatus.call(user: user),
        paths: paths_json
      }
    end

    def rows_payload
      {
        subject: subject,
        view: view,
        page: page,
        per_page: PER_PAGE,
        total: current_result.fetch(:total),
        total_pages: total_pages(current_result.fetch(:total)),
        landing_queue: landing_queue_json,
        items: current_result.fetch(:items),
        lanes: lanes_json,
        kanban_limit: view == "kanban" ? kanban_limit : nil
      }
    end

    def section
      @section ||= params[:section].to_s.presence_in(SECTIONS) || "full"
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

    def current_filter
      case subject
      when "job"
        jobs_filter
      when "workflow"
        workflows_filter
      else
        epics_filter
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
                folder_pref_view ||
                user.dashboard_preferences.dig(subject.pluralize, "last_view").to_s.presence_in(VIEWS) ||
                user.dashboard_preferences["last_view"].to_s.presence_in(VIEWS) ||
                DEFAULT_VIEW
    end

    def folder_pref_view
      slot = active_folder_preference_slot
      return slot["view"].to_s.presence_in(VIEWS) if slot.key?("view")

      folder_preference_default("view").to_s.presence_in(VIEWS)
    end

    def page
      @page ||= [ Integer(params[:page], exception: false).to_i, 1 ].max
    end

    def active_repo_ids
      @active_repo_ids ||= active_repositories_scope.pluck(:id)
    end

    def active_repositories_scope
      return Repository.active if subject == "epic"
      return Repository.active if mine_scope? || team_scope? || user_scope? || claimable_scope?

      Repository.active.where(user_id: user.id)
    end

    def jobs_base_scope
      @jobs_base_scope ||= apply_ownership_scope(
        Job.where(repository_id: active_repo_ids),
        :job
      )
    end

    def epics_base_scope
      @epics_base_scope ||= apply_ownership_scope(Epic.where(repository_id: active_repo_ids), :epic)
    end

    def workflows_base_scope
      @workflows_base_scope ||= apply_ownership_scope(
        Workflow.joins(:job).where(jobs: { repository_id: active_repo_ids }),
        :workflow
      )
    end

    def active_smart_folder
      @active_smart_folder ||= begin
        id = Integer(params[:smart_folder_id], exception: false)
        if id.nil? && !param_key?(:smart_folder_id)
          id = Integer(user.dashboard_preferences.dig(subject.pluralize, "last_smart_folder_id"), exception: false)
        end

        if id
          SmartFolder.for_subject(subject)
                     .where("user_id IS NULL OR user_id = ?", user.id)
                     .find_by(id: id)
        elsif default_inbox_smart_folder?
          SmartFolder.find_builtin_by_attention("inbox")
        end
      end
    end

    def active_folder_key_for_prefs
      @active_folder_key_for_prefs ||= begin
        id = Integer(params[:smart_folder_id], exception: false)
        unless id || param_key?(:smart_folder_id)
          id = Integer(user.dashboard_preferences.dig(subject.pluralize, "last_smart_folder_id"), exception: false)
        end

        id&.to_s || "null"
      end
    end

    def active_folder_builtin_key
      @active_folder_builtin_key ||= begin
        id_str = active_folder_key_for_prefs
        return "null" if id_str == "null"

        folder = SmartFolder.for_subject(subject).where(user_id: nil).builtin.find_by(id: id_str.to_i)
        return "null" unless folder

        definition = SmartFolder::BUILTINS_BY_SUBJECT.fetch(subject, []).find do |candidate|
          candidate.fetch(:name) == folder.name
        end
        definition&.fetch(:key) || "null"
      end
    end

    def active_folder_preference_slot
      user.dashboard_preferences.dig(subject.pluralize, "folder_prefs", active_folder_key_for_prefs) || {}
    end

    def folder_preference_default(key)
      FOLDER_PREFERENCE_DEFAULTS.dig([ subject, active_folder_builtin_key ], key)
    end

    def dashboard_sort(subject_name = subject)
      normalized_subject = subject_name.to_s.delete_suffix("s")
      subject_preferences = user.dashboard_preferences.fetch(normalized_subject.pluralize)
      slot = normalized_subject == subject ? active_folder_preference_slot : {}

      column = params[:sort_column].to_s.presence_in(User::DASHBOARD_SORT_COLUMNS.fetch(normalized_subject)) ||
               slot["sort_column"].to_s.presence_in(User::DASHBOARD_SORT_COLUMNS.fetch(normalized_subject)) ||
               folder_sort_default(normalized_subject, "sort_column").to_s.presence_in(User::DASHBOARD_SORT_COLUMNS.fetch(normalized_subject)) ||
               subject_preferences["sort_column"].to_s.presence_in(User::DASHBOARD_SORT_COLUMNS.fetch(normalized_subject)) ||
               User::DASHBOARD_SORT_DEFAULTS.fetch(normalized_subject).fetch("column")
      direction = params[:sort_direction].to_s.presence_in(User::DASHBOARD_SORT_DIRECTIONS) ||
                  slot["sort_direction"].to_s.presence_in(User::DASHBOARD_SORT_DIRECTIONS) ||
                  folder_sort_default(normalized_subject, "sort_direction").to_s.presence_in(User::DASHBOARD_SORT_DIRECTIONS) ||
                  subject_preferences["sort_direction"].to_s.presence_in(User::DASHBOARD_SORT_DIRECTIONS) ||
                  User::DASHBOARD_SORT_DEFAULTS.fetch(normalized_subject).fetch("direction")

      return { column: column, direction: direction } if normalized_subject == "job"

      { "column" => column, "direction" => direction }
    end

    def folder_sort_default(subject_name, key)
      return unless subject_name == subject

      folder_preference_default(key)
    end

    def default_inbox_smart_folder?
      subject == "job" &&
        params[:view] == "list" &&
        !param_key?(:smart_folder_id) &&
        !filter_param_present?
    end

    def filter_param_present?
      params[Filters::QueryParam::PARAM_NAME].present? ||
        Jobs::Filter::LEGACY_URL_KEYS.any? { |key| params[key].present? }
    end

    def param_key?(key)
      params.key?(key) || params.key?(key.to_s)
    end

    def jobs_result
      ensure_landing_queue_snapshot! if landing_queue_visible?
      scope = filtered_jobs_scope
      total = scope.count
      scope = scope.with_latest_workflow_snapshot.preload(:repository, :user, :owner_user, :claimed_by_user, :tags, :workflows, :runs, chat_proposals: [ :chat_session, :messages ], epic: { chat_proposals: [ :chat_session, :messages ] })
      jobs = sorted_jobs(scope).to_a
      @current_jobs = jobs
      items = jobs.map { |job| job_json(job) }

      { total: total, items: items }
    end

    def epics_result
      scope = filtered_epics_scope.includes(:owner, :repository, :owner_user, :jobs)
      total = scope.count
      items = paginate(apply_sort(scope, :epic)).map { |epic| epic_json(epic) }

      { total: total, items: items }
    end

    def workflows_result
      scope = filtered_workflows_scope.includes(:steps, job: [ :repository, :user, :owner_user ])
      total = scope.count
      items = paginate(apply_sort(scope, :workflow)).map { |workflow| workflow_json(workflow) }

      { total: total, items: items }
    end

    def jobs_filter
      @jobs_filter ||= Jobs::Filter.from_params(params, smart_folder: active_smart_folder_for_filter, user: user)
    end

    def filtered_jobs_scope
      @filtered_jobs_scope ||= jobs_filter.apply(jobs_base_scope)
    end

    def epics_filter
      @epics_filter ||= Epics::Filter.from_params(params, smart_folder: active_smart_folder_for_filter, user: user)
    end

    def filtered_epics_scope
      @filtered_epics_scope ||= begin
        scope = epics_base_scope
        scope = scope.where.not(state: Epic::ARCHIVED_STATE) unless epics_filter.includes_archived_state?
        epics_filter.apply(scope)
      end
    end

    def workflows_filter
      @workflows_filter ||= Workflows::Filter.from_params(params, smart_folder: active_smart_folder_for_filter, user: user)
    end

    def active_smart_folder_for_filter
      url_filter.active? ? nil : active_smart_folder
    end

    def url_filter
      @url_filter ||= case subject
      when "job"
        Jobs::Filter.from_params(params, user: user)
      when "workflow"
        Workflows::Filter.from_params(params, user: user)
      else
        Epics::Filter.from_params(params, user: user)
      end
    end

    def filtered_workflows_scope
      @filtered_workflows_scope ||= begin
        scope = workflows_base_scope
        workflows_filter.apply(scope)
      end
    end

    def counts
      @counts ||= {
        jobs: jobs_base_scope.count,
        epics: epics_base_scope.where.not(state: Epic::ARCHIVED_STATE).count,
        workflows: workflows_base_scope.count
      }
    end

    def apply_sort(scope, subject_name)
      sort = dashboard_sort(subject_name)
      column = sort_value(sort, "column")
      direction = sort_value(sort, "direction") == "asc" ? :asc : :desc

      case [ subject_name.to_s, column ]
      when [ "job", "title" ]
        scope.reorder(Job.arel_table[:issue_title].public_send(direction), Job.arel_table[:id].public_send(direction))
      when [ "job", "state" ]
        scope.reorder(Job.arel_table[:state].public_send(direction), Job.arel_table[:id].public_send(direction))
      when [ "job", "repository" ]
        scope.joins(:repository).reorder(Repository.arel_table[:name].public_send(direction), Job.arel_table[:id].public_send(direction))
      when [ "job", "landing_queue_position" ]
        scope.reorder(Arel.sql("COALESCE(jobs.approved_at, jobs.updated_at) #{direction.to_s.upcase}"), Job.arel_table[:id].public_send(direction))
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

    def sorted_jobs(scope)
      return landing_queue_sorted_jobs(scope) if landing_queue_position_sort?

      paginate(apply_sort(scope, :job))
    end

    def landing_queue_position_sort?
      landing_queue_visible? && sort_value(dashboard_sort(:job), "column") == "landing_queue_position"
    end

    def landing_queue_sorted_jobs(scope)
      direction = sort_value(dashboard_sort(:job), "direction") == "asc" ? :asc : :desc
      sorted = scope.reorder(
        Arel.sql("CASE WHEN jobs.landing_queue_position IS NULL THEN 1 ELSE 0 END ASC"),
        Job.arel_table[:landing_queue_position].public_send(direction),
        Job.arel_table[:id].public_send(direction)
      )
      paginate(sorted)
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
      owner_user = job_owner_user(job)

      {
        type: "job",
        id: job.id,
        kind: job.kind,
        title: job.issue_title.presence || job.kind.humanize,
        title_pending: job.title_pending?,
        state: job.state,
        summary_state: summary_state(job),
        validity: job.validity,
        priority: job.priority,
        total_cost_usd: job.display_total_cost_usd&.to_f,
        issue_number: job.issue_number,
        issue_url: App::Presentation.job_issue_url(job),
        branch_name: job.branch_name,
        pr_number: job.pr_number || job.external_pr_number,
        active_workflow_trigger_kind: active_workflow_trigger_kind(job),
        latest_workflow_id: job.latest_workflow_id,
        latest_workflow_trigger_kind: job.latest_workflow_trigger_kind,
        pr_url: job.pr_number.present? ? App::Presentation.job_pr_url(job) : App::Presentation.external_pr_url(job),
        latest_workflow_state: App::Presentation.workflow_dashboard_state(job.latest_workflow_state, job.latest_workflow_trigger_kind),
        landing_queue_position: landing_queue_position_for(job),
        landing_queue_blocked_reason: landing_queue_blocked_reason_for(job),
        landing_queue_entry_key: landing_queue_entry_key_for(job),
        retry_state: ::App::RetryState.for(job),
        created_at: job.created_at&.iso8601,
        updated_at: job.updated_at&.iso8601,
        started_at: job.started_at&.iso8601,
        finished_at: job.finished_at&.iso8601,
        approved_at: job.approved_at&.iso8601,
        owner_user_id: job.owner_user_id,
        owner_user: owner_user_json(owner_user),
        claimed_at: job.claimed_at&.iso8601,
        claimed_by_user: claim_owner_json(job.claimed_by_user),
        claimed_by_current_user: job.claimed_by_user_id == user.id,
        dependencies_overridden_at: job.dependencies_overridden_at&.iso8601,
        last_feedback_addressed_at: job.last_feedback_addressed_at&.iso8601,
        last_seen_comment_at: job.last_seen_comment_at&.iso8601,
        pr_mergeable_checked_at: job.pr_mergeable_checked_at&.iso8601,
        workflows_count: job.workflows.size,
        repository: repository_json(job.repository),
        epic: job_epic_json(job.epic),
        owner_badge: owner_badge_for(owner_user),
        tags: job.tags.map { |tag| tag_json(tag) },
        source_chat: App::JobSourceChat.for(job),
        needs_attention: job.needs_attention?,
        needs_attention_reason: job.needs_attention_reason,
        paths: {
          job_path: job_path(job),
          source_path: source_job_path(job)
        }
      }
    end

    def job_epic_json(epic)
      return nil unless epic

      {
        id: epic.id,
        number: epic.number,
        display_number: epic.slug,
        path: epic_path(epic)
      }
    end

    def claim_owner_json(owner)
      return unless owner

      {
        id: owner.id,
        display_name: owner.display_name,
        profile_path: profile_path(owner)
      }
    end

    def epic_json(epic)
      owner_user = epic_owner_user(epic)

      {
        type: "epic",
        id: epic.id,
        number: epic.number,
        display_number: epic.slug,
        title: epic.title,
        description: epic.description.to_s,
        state: epic.state,
        stuck: epic.stuck?,
        all_jobs_closed: epic.all_jobs_closed?,
        owner: owner_json(epic.owner),
        owned_by_current_user: epic.owner_user_id == user.id || epic.claimed_by?(user),
        claimable: epic.claimable?,
        owner_badge: owner_badge_for(owner_user, claimable: epic.claimable?),
        claimed_at: epic.claimed_at&.iso8601,
        auto_approve_mode: epic.auto_approve_mode,
        owner_user_id: owner_user&.id,
        owner_status: epic_owner_status(epic),
        owner_user: owner_user_json(owner_user),
        jobs_count: epic.jobs.size,
        landed_jobs_count: epic_landed_jobs_count(epic),
        job_state_counts: epic_job_state_counts(epic),
        created_at: epic.created_at&.iso8601,
        updated_at: epic.updated_at&.iso8601,
        done_at: epic.done_at&.iso8601,
        archived_at: epic.archived_at&.iso8601,
        repository: repository_json(epic.repository),
        paths: {
          epic_path: epic_path(epic),
          edit_epic_path: edit_epic_path(epic),
          app_state_path: "/api/v1/app/epics/#{epic.id}/state",
          app_claim_path: "/api/v1/app/epics/#{epic.id}/claim",
          app_unclaim_path: "/api/v1/app/epics/#{epic.id}/unclaim"
        }
      }
    end

    def epic_landed_jobs_count(epic)
      epic.jobs.count { |job| job.closed? && Epic::MERGED_JOB_CLOSURE_REASONS.include?(job.closure_reason) }
    end

    def epic_job_state_counts(epic)
      epic.jobs.each_with_object(Hash.new(0)) do |job, counts|
        state = if job.closure_reason == "preempted" || job.closure_reason&.start_with?("external_pr_")
                  "preempted"
                else
                  job.state
                end
        counts[state] += 1
      end.to_h
    end

    def owner_json(owner)
      return nil unless owner

      {
        id: owner.id,
        email_address: owner.email_address,
        display_name: owner.team_display_name,
        profile_path: profile_path(owner)
      }
    end

    def workflow_json(workflow)
      job = workflow.job
      owner_user = job_owner_user(job)

      {
        type: "workflow",
        id: workflow.id,
        slug: workflow.slug,
        path: App::WorkflowNavigation.path(workflow),
        state: App::Presentation.workflow_dashboard_state(workflow.state, workflow.trigger_kind),
        trigger_kind: workflow.trigger_kind,
        agent_provider: workflow.agent_provider,
        created_at: workflow.created_at&.iso8601,
        updated_at: workflow.updated_at&.iso8601,
        started_at: workflow.started_at&.iso8601,
        finished_at: workflow.finished_at&.iso8601,
        cleaned_up_at: workflow.cleaned_up_at&.iso8601,
        steps_count: workflow.steps.size,
        job: {
          id: job.id,
          title: job.issue_title.presence || job.kind.humanize,
          title_pending: job.title_pending?,
          state: job.state,
          repository: repository_json(job.repository),
          owner_user: owner_user_json(owner_user),
          owner_badge: owner_badge_for(owner_user),
          path: job_path(job)
        }
      }
    end

    def epic_owner_status(epic)
      owner_user = epic_owner_user(epic)
      return "unclaimed" if owner_user.nil?
      return "mine" if owner_user.id == user.id

      "other_owned"
    end

    def job_owner_user(job)
      job.owner_user || job.user
    end

    def epic_owner_user(epic)
      epic.owner_user || epic.owner
    end

    def owner_badge_for(owner_user, claimable: false)
      return nil if team_user_count <= 1
      return { label: "Claimable", kind: "claimable" } if claimable && owner_user.nil?
      return nil if owner_user.nil? || owner_user.id == user.id

      {
        label: owner_user.team_display_name,
        kind: "other_user"
      }
    end

    def smart_folders_json
      folders = SmartFolder.for_subject(subject)
                           .where("user_id IS NULL OR user_id = ?", user.id)
                           .order(Arel.sql("CASE WHEN user_id IS NULL THEN 0 ELSE 1 END"), :position, :id)

      folders.filter_map do |folder|
        count = smart_folder_count(folder)
        next unless smart_folder_visible?(folder, count)

        {
          id: folder.id,
          name: folder.name,
          kind: folder.kind,
          position: folder.position,
          subject_type: folder.subject_type,
          visibility: folder.visibility.to_s,
          count: count,
          active: active_smart_folder&.id == folder.id,
          filter: folder.filter,
          path: dashboard_path_for(subject, smart_folder_id: folder.id)
        }
      end
    end

    def smart_folder_visible?(folder, count)
      return true unless folder.builtin?
      return true if active_smart_folder&.id == folder.id
      return count.positive? if folder.visibility == :when_present

      true
    end

    def smart_folder_count(folder)
      case subject
      when "job"
        Jobs::Filter.from_tree(folder.filter, user: user).apply(jobs_base_scope).count
      when "workflow"
        Workflows::Filter.from_tree(folder.filter, user: user).apply(workflows_base_scope).count
      else
        filter = Epics::Filter.from_tree(folder.filter, user: user)
        scope = epics_base_scope
        scope = scope.where.not(state: Epic::ARCHIVED_STATE) unless filter.includes_archived_state?
        filter.apply(scope).count
      end
    end

    def preferences_json
      table = subject.pluralize
      {
        sort: dashboard_sort(subject),
        visible_columns: user.dashboard_visible_columns(subject),
        kanban_lanes: user.dashboard_visible_kanban_lanes(subject),
        ownership_scope: ownership_scope,
        owner_user_id: selected_owner_user&.id,
        owner_id: selected_owner_user&.id,
        raw: user.dashboard_preferences.fetch(table)
      }
    end

    def controls_json
      {
        views: VIEWS,
        ownership_scopes: ownership_scope_options_json,
        owners: owner_options.map { |owner| owner_option_json(owner) },
        sort_columns: User::DASHBOARD_SORT_COLUMNS.fetch(subject),
        sort_directions: User::DASHBOARD_SORT_DIRECTIONS,
        columns: column_options_json,
        kanban_lanes: kanban_lane_options_json,
        filter_schema: Filters::Schema.for(subject: subject.to_sym, user: user),
        filter_suggestions: filter_suggestions_json
      }
    end

    def filter_suggestions_json
      Filters::Suggestions.for(
        user: user,
        surface: "dashboard",
        subject: subject,
        active_tree: current_filter.to_h
      )
    end

    def ownership_scope_json
      {
        scope: ownership_scope,
        owner_user_id: selected_owner_user&.id,
        owner_user: owner_user_json(selected_owner_user)
      }
    end

    def ownership_json
      {
        scope: ownership_scope,
        owner_id: selected_owner_user&.id,
        team_user_count: team_user_count,
        badges_visible: team_user_count > 1
      }
    end

    def ownership_scope_options_json
      OWNERSHIP_SCOPES.map do |scope|
        {
          value: scope,
          label: scope.humanize
        }
      end
    end

    def owner_option_json(owner)
      {
        id: owner.id,
        label: owner.team_display_name,
        current: owner.id == selected_owner_user&.id
      }
    end

    def landing_queue_json
      json = {
        visible: landing_queue_visible?,
        paused: user.landing_paused?,
        toggle_path: "/api/v1/app/dashboard/landing_pause"
      }
      json[:entries] = landing_queue_entries_json if landing_queue_visible?
      json
    end

    def landing_queue_chrome_json
      {
        visible: landing_queue_visible?,
        paused: user.landing_paused?,
        toggle_path: "/api/v1/app/dashboard/landing_pause"
      }
    end

    def health_blocked_repositories_json
      @health_blocked_repositories_json ||= user.repositories.active.select { |repo| repo.main_health_broken? || repo.main_health_inconclusive? }.map do |repo|
        repair_status = MainHealthChangedService.new(repo).repair_status
        {
          id: repo.id,
          slug: repo.slug,
          main_health: repo.main_health,
          ci_health: repo.ci_health,
          grader_health: repo.grader_health,
          landing_paused: repo.landing_paused,
          repository_path: repository_path(repo),
          repair_path: "/api/v1/app/repositories/#{repo.id}/repair_main_branch",
          main_branch_repair: main_branch_repair_json(repair_status)
        }
      end
    end

    def main_branch_repair_json(status)
      {
        enabled: status[:enabled],
        failed_open_jobs_count: status[:failed_open_jobs_count],
        max_open_failed_jobs: status[:max_open_failed_jobs],
        blocked_reason: status[:blocked_reason],
        can_request: status[:can_request],
        can_spawn: status[:can_spawn],
        blocking_job: repair_job_json(status[:blocking_job]),
        failed_jobs: status[:failed_jobs].map { |job| repair_job_json(job) }
      }
    end

    def repair_job_json(job)
      return nil unless job

      {
        id: job.id,
        slug: job.slug,
        state: job.state,
        title: job.title,
        job_path: job_path(job)
      }
    end

    def landing_queue_visible?
      subject == "job" && active_smart_folder&.attention_preset == "landing_queue"
    end

    def ensure_landing_queue_snapshot!
      return if @landing_queue_snapshot_checked

      @landing_queue_snapshot_checked = true
      candidates = jobs_base_scope.where(state: %w[ approved landing ])
      return unless candidates.where(landing_queue_cached_at: nil).exists?

      LandingQueueProcessor.refresh_snapshot!(jobs_base_scope)
    end

    def landing_queue_position_for(job)
      job.landing_queue_position if landing_queue_visible?
    end

    def landing_queue_blocked_reason_for(job)
      job.landing_queue_blocked_reason if landing_queue_visible?
    end

    def landing_queue_entry_key_for(job)
      if landing_queue_visible?
        job.landing_queue_entry_key.presence || "job:#{job.id}"
      end
    end

    def landing_queue_entries
      return [] unless landing_queue_visible?

      @landing_queue_entries ||= current_landing_queue_jobs.group_by { |job| job.landing_queue_entry_key.presence || "job:#{job.id}" }
    end

    def landing_queue_entries_json
      blocker_jobs_by_id = landing_queue_blocker_jobs_by_id

      landing_queue_entries.map do |key, jobs|
        blocker_ids = jobs.flat_map { |job| Array(job.landing_queue_blocker_job_ids) }.uniq
        {
          key: key,
          position: jobs.filter_map(&:landing_queue_entry_position).min,
          job_ids: jobs.map(&:id),
          blocker_jobs: blocker_ids.filter_map { |id| blocker_jobs_by_id[id] }.map { |job| landing_queue_blocker_job_json(job, key) },
          dependency_edges: jobs.flat_map { |job| Array(job.landing_queue_dependency_edges) }.uniq
        }
      end
    end

    def current_landing_queue_jobs
      current_result if @current_jobs.nil?
      @current_jobs || []
    end

    def landing_queue_blocker_jobs_by_id
      ids = current_landing_queue_jobs.flat_map { |job| Array(job.landing_queue_blocker_job_ids) }.uniq
      return {} if ids.empty?

      Job.where(id: ids).includes(:epic).index_by(&:id)
    end

    def landing_queue_blocker_job_json(job, entry_key)
      json = {
        id: job.id,
        title: job.issue_title.presence || job.slug,
        job_path: "/jobs/#{job.id}",
        state: job.state,
        pr_number: job.pr_number || job.external_pr_number,
        pr_path: App::Presentation.job_pr_url(job) || App::Presentation.external_pr_url(job)
      }
      if job.epic_id != landing_queue_entry_epic_id(entry_key)
        json[:epic_id] = job.epic_id
        json[:epic_title] = job.epic&.title
      end
      json
    end

    def landing_queue_entry_epic_id(entry_key)
      match = entry_key.to_s.match(/\Aepic:(\d+)\z/)
      match ? match[1].to_i : nil
    end

    def column_options_json
      table = subject.pluralize
      {
        required: required_columns_for(table).map { |column| column_json(table, column) },
        optional: User::DASHBOARD_OPTIONAL_COLUMNS.fetch(table).map { |column| column_json(table, column) }
      }
    end

    def required_columns_for(table)
      return %w[checkbox landing_queue_position landing_queue_blocked_reason issue] if table == "jobs" && landing_queue_visible?

      User::DASHBOARD_REQUIRED_COLUMNS.fetch(table)
    end

    def column_json(table, column)
      {
        key: column,
        title: COLUMN_LABELS.dig(table, column) || column.humanize
      }
    end

    def kanban_lane_options_json
      User::DASHBOARD_KANBAN_LANES.fetch(subject.pluralize).map do |lane|
        {
          key: lane,
          title: kanban_lane_title(lane)
        }
      end
    end

    def kanban_lane_title(lane)
      return JOB_KANBAN_LANES.find { |definition| definition.fetch(:key) == lane }&.fetch(:title) || lane.humanize if subject == "job"

      lane.humanize
    end

    def paths_json
      {
        dashboard_path: dashboard_path_for(subject),
        dashboard_jobs_path: dashboard_jobs_path,
        dashboard_epics_path: dashboard_epics_path,
        dashboard_workflows_path: dashboard_workflows_path,
        new_epic_path: new_epic_path,
        new_job_path: new_job_path,
        app_dashboard_path: "/api/v1/app/dashboard"
      }
    end

    def dashboard_path_for(target_subject, extra = {})
      extra = ownership_query_params.merge(extra)
      case target_subject.to_s
      when "epic"
        dashboard_epics_path(extra)
      when "workflow"
        dashboard_workflows_path(extra)
      else
        dashboard_jobs_path(extra)
      end
    end

    def ownership_query_params
      query = { ownership_scope: ownership_scope }
      query[:owner_id] = selected_owner_user.id if ownership_scope == "user"
      query
    end

    def repository_json(repository)
      {
        id: repository.id,
        slug: repository.slug,
        repository_path: repository_path(repository)
      }
    end

    def tag_json(tag)
      {
        id: tag.id,
        name: tag.name,
        color: tag.color
      }
    end

    def owner_user_json(owner)
      return nil unless owner

      {
        id: owner.id,
        name: owner.display_name,
        email_address: owner.email_address
      }
    end

    def summary_state(job)
      return "preempted" if job.closure_reason == "preempted"
      return "preempted" if job.closure_reason&.start_with?("external_pr_")

      job.state
    end

    def active_workflow_trigger_kind(job)
      return nil unless summary_state(job) == "running"

      job.active_workflow_trigger_kind
    end

    def ownership_param_present?
      params.key?(:scope) || params.key?(:ownership_scope) || params.key?(:owner_id) || params.key?(:owner_user_id)
    end

    def legacy_scope_param?
      params.key?(:scope) && !params.key?(:ownership_scope)
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
