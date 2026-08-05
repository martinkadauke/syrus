class CreateProviderAvailabilityEvidences < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_availability_evidences do |t|
      t.references :user, null: false, foreign_key: true
      t.references :run, foreign_key: true
      t.references :chat_session, foreign_key: true
      t.references :chat_message, foreign_key: true
      t.string :provider, limit: 32, null: false
      t.string :account_id, limit: 128
      t.string :model, limit: 100
      t.string :status, limit: 64, null: false
      t.string :source, limit: 64, null: false
      t.datetime :observed_at, null: false
      t.integer :http_status
      t.json :details
      t.timestamps
    end

    unless index_exists?(:provider_availability_evidences, [ :user_id, :provider, :account_id, :model, :observed_at ], name: "idx_provider_evidence_scope_observed")
      add_index :provider_availability_evidences,
                [ :user_id, :provider, :account_id, :model, :observed_at ],
                name: "idx_provider_evidence_scope_observed"
    end

    unless index_exists?(:provider_availability_evidences, [ :provider, :status, :observed_at ], name: "idx_provider_evidence_status_observed")
      add_index :provider_availability_evidences,
                [ :provider, :status, :observed_at ],
                name: "idx_provider_evidence_status_observed"
    end
  end
end
