class RenameClaudeApiKeyToClaudeOauthTokenOnUsers < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :claude_api_key, :claude_oauth_token
  end
end
