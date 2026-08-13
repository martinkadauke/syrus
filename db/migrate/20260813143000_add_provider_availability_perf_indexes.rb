class AddProviderAvailabilityPerfIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :provider_availability_evidences,
      [ :user_id, :provider, :status, :observed_at ],
      name: "idx_provider_evidence_user_provider_status_observed",
      if_not_exists: true

    add_index :provider_availability_evidences,
      [ :provider, :status, :observed_at ],
      name: "idx_provider_evidence_provider_status_observed",
      if_not_exists: true

    add_index :runs,
      [ :user_id, :agent_provider, :state, :finished_at ],
      name: "idx_runs_user_provider_state_finished",
      if_not_exists: true

    add_index :runs,
      [ :agent_provider, :state, :finished_at ],
      name: "idx_runs_provider_state_finished",
      if_not_exists: true
  end
end
