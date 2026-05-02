class NullSelfReferentialExternalPrNumbers < ActiveRecord::Migration[8.1]
  # Cleans up data created by a bug where the preempted-PR detector
  # used `closedByPullRequestsReferences` (which includes Syrus's OWN
  # open PR) without filtering self. That ended up writing
  # external_pr_number = pr_number on Jobs Syrus had opened a PR for,
  # making the show page render the same PR twice. Fix in code went
  # out alongside this migration; this just scrubs the bad rows.
  def up
    execute("UPDATE jobs SET external_pr_number = NULL WHERE external_pr_number = pr_number")
  end

  def down
    # Irreversible — from a NULL we can't tell whether the bug wrote
    # it or it was genuinely never set. Migration is forward-only.
  end
end
