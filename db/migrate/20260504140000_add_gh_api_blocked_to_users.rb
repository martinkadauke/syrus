class AddGhApiBlockedToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :gh_api_blocked_at,     :datetime
    add_column :users, :gh_api_blocked_reason, :text
  end
end
