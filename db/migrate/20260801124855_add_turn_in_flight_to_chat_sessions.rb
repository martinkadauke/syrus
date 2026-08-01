class AddTurnInFlightToChatSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_sessions, :turn_in_flight, :boolean, default: false, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE chat_sessions
          SET turn_in_flight = EXISTS (
            SELECT 1
            FROM chat_messages latest_user_messages
            WHERE latest_user_messages.chat_session_id = chat_sessions.id
              AND latest_user_messages.role = 'user'
              AND NOT EXISTS (
                SELECT 1
                FROM chat_messages newer_user_messages
                WHERE newer_user_messages.chat_session_id = latest_user_messages.chat_session_id
                  AND newer_user_messages.role = 'user'
                  AND (
                    newer_user_messages.created_at > latest_user_messages.created_at
                    OR (
                      newer_user_messages.created_at = latest_user_messages.created_at
                      AND newer_user_messages.id > latest_user_messages.id
                    )
                  )
              )
              AND NOT EXISTS (
                SELECT 1
                FROM chat_messages later_response_messages
                WHERE later_response_messages.chat_session_id = latest_user_messages.chat_session_id
                  AND later_response_messages.role <> 'user'
                  AND (
                    later_response_messages.created_at > latest_user_messages.created_at
                    OR (
                      later_response_messages.created_at = latest_user_messages.created_at
                      AND later_response_messages.id > latest_user_messages.id
                    )
                  )
              )
          )
        SQL
      end
    end
  end
end
