class AddLastSeenCommentAtToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :last_seen_comment_at, :datetime
  end
end
