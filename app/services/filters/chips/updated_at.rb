module Filters
  module Chips
    class UpdatedAt < DateColumn
      filter_name "updated_at"
      label "Updated"
      column :updated_at
      # updated_at is NOT NULL — is_set / is_unset are meaningless.
      operators :before, :after, :between, :within_last, :more_than_ago
    end
  end
end
