class AddApiTokenToUsers < ActiveRecord::Migration[8.1]
  # Per-user API token for the v1 admin REST API. Encrypted with
  # `deterministic: true` so we can WHERE on it for the auth
  # lookup without storing a plaintext or extra-table digest.
  # Token rotates on demand via the credentials page; admin-only
  # API endpoints require it via `Authorization: Bearer <token>`.
  def change
    add_column :users, :api_token, :string
    add_index  :users, :api_token, unique: true
  end
end
