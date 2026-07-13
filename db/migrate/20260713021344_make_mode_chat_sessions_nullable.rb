class MakeModeChatSessionsNullable < ActiveRecord::Migration[8.1]
  def up
    if column_exists?(:chat_sessions, :mode)
      change_column_null :chat_sessions, :mode, true
      change_column_default :chat_sessions, :mode, from: "planning", to: nil
    end
  end

  def down
    if column_exists?(:chat_sessions, :mode)
      execute "UPDATE chat_sessions SET mode = 'planning' WHERE mode IS NULL"
      change_column_null :chat_sessions, :mode, false
      change_column_default :chat_sessions, :mode, from: nil, to: "planning"
    end
  end
end
