module Steps
  # Final push after a follow-up workflow recovered from a remote branch
  # advance by rebasing local feedback work onto the current PR branch.
  class PushAfterRebase < Push
  end
end
