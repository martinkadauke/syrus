module PendingActions
  # Creates a new direct Job from committed branch changes and immediately
  # dispatches a CodingHandoff workflow (graders → summarize → PR open).
  # Used by the `submit_coding_changes` MCP tool in coding-mode chat sessions.
  class SubmitCodingChanges < Base
    action_key "submit_coding_changes"

    def execute
      repository  = user.repositories.active.find(payload.fetch("repository_id"))
      branch      = payload.fetch("branch").to_s
      description = payload.fetch("description")
      title       = payload["title"].presence
      handoff_branch = "syrus/chat-#{chat_session.id}-handoff-#{action.id}"
      snapshot = CodingHandoffCapture.capture!(
        chat_session: chat_session,
        repository: repository,
        user: user,
        source_branch: branch,
        handoff_branch: handoff_branch
      )
      artifacts = workflow_artifacts(snapshot: snapshot, title: title, description: description)

      # Create the job directly in :queued state to skip the triage → queued
      # transition (which would trigger create_initial_run_if_needed). The
      # CodingHandoff workflow dispatched below replaces the initial workflow.
      job = user.jobs.create!(
        repository: repository,
        kind: "direct",
        issue_title: title || GenerateJobTitleJob::PENDING_TITLE,
        title_pending: title.nil?,
        issue_body: description,
        branch_name: snapshot.fetch("handoff_branch"),
        linked_chat_id: chat_session.id,
        agent_provider: repository.effective_agent_provider,
        state: "queued"
      )

      job.claim_for_coding!
      job.save!

      workflow = job.start_coding_handoff!(artifacts: artifacts)
      raise ArgumentError, "could not start coding handoff (feature may be disabled or state invalid)" unless workflow

      GenerateJobTitleJob.perform_later(job) if title.nil?

      workflow
    rescue CodingHandoffCapture::CaptureError => e
      raise ArgumentError, e.message
    end

    def validate_payload(errors)
      errors.add(:payload, "repository_id is required") unless payload["repository_id"].present?
      errors.add(:payload, "branch is required") unless payload["branch"].present?
      errors.add(:payload, "title is required") unless payload["title"].present?
      errors.add(:payload, "description is required") unless payload["description"].present?
    end

    def action_detail
      "branch: #{payload["branch"]}, repository_id: #{payload["repository_id"]}"
    end

    private

    def workflow_artifacts(snapshot:, title:, description:)
      {
        "coding_handoff" => snapshot,
        "pr_title" => pr_title(title: title, description: description),
        "pr_body" => pr_body(description: description, snapshot: snapshot),
        "summary" => description.to_s,
        "test_plan" => {
          "steps" => [],
          "notes" => nil
        }
      }
    end

    def pr_title(title:, description:)
      title.presence || description.to_s.lines.first.to_s.strip.presence || "Coding handoff from chat ##{chat_session.id}"
    end

    def pr_body(description:, snapshot:)
      changed_files = Array(snapshot["changed_files"]).presence || [ "(unknown)" ]
      <<~BODY.strip
        #{description}

        ## Coding handoff

        Captured chat workspace commit `#{snapshot["head_sha"]}` from `#{snapshot["source_branch"]}` and published immutable handoff branch `#{snapshot["handoff_branch"]}`.

        Changed files:
        #{changed_files.map { |path| "- `#{path}`" }.join("\n")}
      BODY
    end
  end
end
