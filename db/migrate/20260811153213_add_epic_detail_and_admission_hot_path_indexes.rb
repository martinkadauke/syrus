class AddEpicDetailAndAdmissionHotPathIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :chat_messages,
              [ :proposal_id, :id ],
              name: "idx_chat_messages_proposal_id_id",
              if_not_exists: true

    add_index :runs,
              [ :user_id, :agent_provider, :state, :finished_at, :updated_at, :id ],
              name: "idx_runs_user_provider_state_recent",
              if_not_exists: true

    add_index :runs,
              [ :state, :step_id ],
              name: "idx_runs_state_step_id",
              if_not_exists: true

    add_index :steps,
              [ :kind, :workflow_id ],
              name: "idx_steps_kind_workflow_id",
              if_not_exists: true

    add_index :job_dependencies,
              [ :depends_on_job_id, :job_id, :id ],
              name: "idx_job_dependencies_depends_on_job_job_id",
              if_not_exists: true

    add_index :epic_dependencies,
              [ :epic_id, :depends_on_job_id, :id ],
              name: "idx_epic_dependencies_epic_job_id",
              if_not_exists: true

    add_index :epic_dependencies,
              [ :epic_id, :depends_on_epic_id, :id ],
              name: "idx_epic_dependencies_epic_epic_id",
              if_not_exists: true
  end
end
