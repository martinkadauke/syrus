class AddSyrusFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, null: false, default: false
    add_column :users, :claude_api_key, :string
    add_column :users, :github_token, :string
  end
end
