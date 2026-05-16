module Filters
  module Chips
    class CreatedAt < DateColumn
      filter_name "created_at"
      label "Created"
      column :created_at
      # created_at is NOT NULL — is_set / is_unset are meaningless.
      operators :before, :after, :between, :within_last, :more_than_ago
    end
  end
end
