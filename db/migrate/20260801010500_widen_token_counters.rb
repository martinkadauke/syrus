class WidenTokenCounters < ActiveRecord::Migration[8.1]
  def change
    change_column :chat_sessions, :cumulative_input_tokens, :bigint, default: 0, null: false
    change_column :chat_sessions, :cumulative_output_tokens, :bigint, default: 0, null: false

    change_column :runs, :input_tokens, :bigint
    change_column :runs, :output_tokens, :bigint
    change_column :runs, :cache_creation_input_tokens, :bigint
    change_column :runs, :cache_read_input_tokens, :bigint
  end
end
