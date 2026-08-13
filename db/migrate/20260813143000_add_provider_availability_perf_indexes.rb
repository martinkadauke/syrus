class AddProviderAvailabilityPerfIndexes < ActiveRecord::Migration[8.1]
  def change
    user_provider_status_observed = [ :user_id, :provider, :status, :observed_at ]
    provider_status_observed = [ :provider, :status, :observed_at ]
    user_provider_state_finished = [ :user_id, :agent_provider, :state, :finished_at ]
    provider_state_finished = [ :agent_provider, :state, :finished_at ]

    unless index_exists?(:provider_availability_evidences, user_provider_status_observed, name: "idx_provider_evidence_user_provider_status_observed")
      add_index :provider_availability_evidences,
        user_provider_status_observed,
        name: "idx_provider_evidence_user_provider_status_observed"
    end

    unless index_exists?(:provider_availability_evidences, provider_status_observed, name: "idx_provider_evidence_provider_status_observed")
      add_index :provider_availability_evidences,
        provider_status_observed,
        name: "idx_provider_evidence_provider_status_observed"
    end

    unless index_exists?(:runs, user_provider_state_finished, name: "idx_runs_user_provider_state_finished")
      add_index :runs,
        user_provider_state_finished,
        name: "idx_runs_user_provider_state_finished"
    end

    unless index_exists?(:runs, provider_state_finished, name: "idx_runs_provider_state_finished")
      add_index :runs,
        provider_state_finished,
        name: "idx_runs_provider_state_finished"
    end
  end
end
