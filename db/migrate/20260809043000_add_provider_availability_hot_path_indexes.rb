class AddProviderAvailabilityHotPathIndexes < ActiveRecord::Migration[8.1]
  def up
    add_index :provider_availability_evidences,
      [ :user_id, :provider, :status, :observed_at, :id ],
      name: "idx_provider_evidence_user_provider_status_recent",
      if_not_exists: true

    add_index :provider_availability_evidences,
      [ :user_id, :provider, :source, :observed_at, :id ],
      name: "idx_provider_evidence_user_provider_source_recent",
      if_not_exists: true

    add_index :runs,
      [ :user_id, :state, :agent_provider, :finished_at, :updated_at, :id ],
      name: "idx_runs_user_state_provider_recent",
      if_not_exists: true

    add_index :jobs,
      [ :user_id, :updated_at, :id ],
      name: "idx_jobs_user_updated_recent",
      if_not_exists: true

    add_index :jobs,
      [ :user_id, :closure_reason ],
      name: "idx_jobs_user_closure_reason",
      if_not_exists: true

    add_index :chat_sessions,
      [ :user_id, :hidden_at, :system_kind, :pinned, :last_message_at, :created_at, :id ],
      name: "idx_chat_sessions_index_order",
      if_not_exists: true

    add_index :chat_messages,
      [ :chat_session_id, :role, :created_at, :id ],
      name: "idx_chat_messages_session_role_created_id",
      if_not_exists: true

    add_index :runs,
      [ :step_id, :state, :id ],
      name: "idx_runs_step_state_id",
      if_not_exists: true
  end

  def down
    remove_index :runs, name: "idx_runs_step_state_id", if_exists: true
    remove_index :chat_messages, name: "idx_chat_messages_session_role_created_id", if_exists: true
    remove_index :chat_sessions, name: "idx_chat_sessions_index_order", if_exists: true
    remove_index :jobs, name: "idx_jobs_user_closure_reason", if_exists: true
    remove_index :jobs, name: "idx_jobs_user_updated_recent", if_exists: true
    remove_index :runs, name: "idx_runs_user_state_provider_recent", if_exists: true
    remove_index :provider_availability_evidences, name: "idx_provider_evidence_user_provider_source_recent", if_exists: true
    remove_index :provider_availability_evidences, name: "idx_provider_evidence_user_provider_status_recent", if_exists: true
  end
end
