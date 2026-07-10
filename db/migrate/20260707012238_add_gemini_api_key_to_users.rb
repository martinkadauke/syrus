class AddGeminiApiKeyToUsers < ActiveRecord::Migration[8.1]
  # Encrypted at the model layer (User `encrypts :gemini_api_key`), same as
  # codex_api_key — a plain text column here.
  def up
    add_column :users, :gemini_api_key, :text unless column_exists?(:users, :gemini_api_key)
  end

  def down
    remove_column :users, :gemini_api_key if column_exists?(:users, :gemini_api_key)
  end
end
