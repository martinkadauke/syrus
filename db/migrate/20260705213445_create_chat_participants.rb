class CreateChatParticipants < ActiveRecord::Migration[8.1]
  def up
    create_table :chat_participants, if_not_exists: true do |t|
      t.references :chat_session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.datetime :joined_at, null: false
      t.datetime :last_read_at

      t.timestamps
    end

    unless index_exists?(:chat_participants, [ :chat_session_id, :user_id ])
      add_index :chat_participants, [ :chat_session_id, :user_id ], unique: true
    end

    # Backfill owner participant for every existing chat session.
    execute <<~SQL
      INSERT INTO chat_participants (chat_session_id, user_id, role, joined_at, created_at, updated_at)
      SELECT id, user_id, 'owner', created_at, #{current_timestamp_sql}, #{current_timestamp_sql}
      FROM chat_sessions
      WHERE NOT EXISTS (
        SELECT 1 FROM chat_participants
        WHERE chat_participants.chat_session_id = chat_sessions.id
          AND chat_participants.user_id = chat_sessions.user_id
      )
    SQL
  end

  def down
    drop_table :chat_participants, if_exists: true
  end

  private

  def current_timestamp_sql
    case ActiveRecord::Base.connection.adapter_name.downcase
    when /mysql/ then "NOW()"
    else "CURRENT_TIMESTAMP"
    end
  end
end
