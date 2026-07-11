class AddSpendingInsightIndexes < ActiveRecord::Migration[8.1]
  def up
    add_index :runs, [ :cost_usd, :created_at ], name: "idx_runs_spending_top_cost" unless index_exists?(:runs, [ :cost_usd, :created_at ], name: "idx_runs_spending_top_cost")
    add_index :runs, [ :created_at, :job_id, :cost_usd ], name: "idx_runs_spending_window_jobs" unless index_exists?(:runs, [ :created_at, :job_id, :cost_usd ], name: "idx_runs_spending_window_jobs")
    add_index :runs, [ :user_id, :created_at, :cost_usd ], name: "idx_runs_spending_user_window" unless index_exists?(:runs, [ :user_id, :created_at, :cost_usd ], name: "idx_runs_spending_user_window")
    add_index :runs, [ :agent_provider, :created_at, :cost_usd ], name: "idx_runs_spending_provider_window" unless index_exists?(:runs, [ :agent_provider, :created_at, :cost_usd ], name: "idx_runs_spending_provider_window")
    add_index :runs, [ :agent_provider, :cost_usd ], name: "idx_runs_spending_provider_cost" unless index_exists?(:runs, [ :agent_provider, :cost_usd ], name: "idx_runs_spending_provider_cost")
    add_index :jobs, [ :closure_reason, :id ], name: "idx_jobs_spending_closure" unless index_exists?(:jobs, [ :closure_reason, :id ], name: "idx_jobs_spending_closure")
    add_index :chat_sessions, [ :cumulative_cost_usd ], name: "idx_chat_sessions_spending_cost" unless index_exists?(:chat_sessions, [ :cumulative_cost_usd ], name: "idx_chat_sessions_spending_cost")
    add_index :chat_sessions, [ :user_id, :cumulative_cost_usd ], name: "idx_chat_sessions_spending_user_cost" unless index_exists?(:chat_sessions, [ :user_id, :cumulative_cost_usd ], name: "idx_chat_sessions_spending_user_cost")
  end

  def down
    remove_index :chat_sessions, name: "idx_chat_sessions_spending_user_cost" if index_exists?(:chat_sessions, name: "idx_chat_sessions_spending_user_cost")
    remove_index :chat_sessions, name: "idx_chat_sessions_spending_cost" if index_exists?(:chat_sessions, name: "idx_chat_sessions_spending_cost")
    remove_index :jobs, name: "idx_jobs_spending_closure" if index_exists?(:jobs, name: "idx_jobs_spending_closure")
    remove_index :runs, name: "idx_runs_spending_provider_cost" if index_exists?(:runs, name: "idx_runs_spending_provider_cost")
    remove_index :runs, name: "idx_runs_spending_provider_window" if index_exists?(:runs, name: "idx_runs_spending_provider_window")
    remove_index :runs, name: "idx_runs_spending_user_window" if index_exists?(:runs, name: "idx_runs_spending_user_window")
    remove_index :runs, name: "idx_runs_spending_window_jobs" if index_exists?(:runs, name: "idx_runs_spending_window_jobs")
    remove_index :runs, name: "idx_runs_spending_top_cost" if index_exists?(:runs, name: "idx_runs_spending_top_cost")
  end
end
