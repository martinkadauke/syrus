class CreateStateTransitions < ActiveRecord::Migration[8.1]
  # Polymorphic audit table for AASM transitions on Job, Workflow,
  # Step, Run. One row per transition. `from_state` / `to_state` /
  # `event_name` capture the AASM move; `source` annotates what
  # caused it (aasm direct, propagate hook, reconciler, operator,
  # system). `metadata` is a JSON bag for caller-specific context
  # (reason strings, evidence). `run_id` cross-links to whichever
  # Run was "current" when the transition fired — invaluable for
  # tying a Job-state move back to the agent turn that caused it.
  def up
    unless table_exists?(:state_transitions)
      create_table :state_transitions do |t|
        t.references :subject, polymorphic: true, null: false
        t.string :from_state, null: false
        t.string :to_state, null: false
        t.string :event_name
        t.string :source, null: false, default: "aasm"
        t.bigint :user_id
        t.bigint :run_id
        # MySQL 8 forbids defaults on JSON columns — backfill below
        # and seed via after_initialize on the model.
        t.json :metadata
        t.datetime :created_at, null: false
      end

      execute "UPDATE state_transitions SET metadata = '{}' WHERE metadata IS NULL"
    end

    unless index_exists?(:state_transitions, %i[ subject_type subject_id created_at ], name: "idx_state_transitions_on_subject_created")
      add_index :state_transitions, %i[ subject_type subject_id created_at ],
                name: "idx_state_transitions_on_subject_created"
    end

    unless index_exists?(:state_transitions, :created_at)
      add_index :state_transitions, :created_at
    end

    unless index_exists?(:state_transitions, :run_id)
      add_index :state_transitions, :run_id
    end

    unless index_exists?(:state_transitions, :user_id)
      add_index :state_transitions, :user_id
    end
  end

  def down
    drop_table :state_transitions, if_exists: true
  end
end
