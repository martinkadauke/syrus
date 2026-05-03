class ClaudeSession < ApplicationRecord
  belongs_to :run

  validates :session_id, presence: true

  # Keep sessions for diagnostics for two weeks after the parent Run
  # reaches a terminal state. After that, ClaudeSessionPruneJob deletes
  # them. Active Runs (queued/running) are never pruned.
  RETAIN_AFTER_TERMINAL = 14.days

  scope :prunable, -> {
    joins(:run).where(runs: { state: %w[ succeeded failed cancelled ] })
               .where("claude_sessions.updated_at < ?", RETAIN_AFTER_TERMINAL.ago)
  }

  # Path Claude Code uses to store its session JSONL on disk:
  # `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl`
  # The "project" component is the absolute cwd with every "/"
  # replaced by "-". Verified empirically — there's no hashing.
  # Example: cwd "/syrus-home/.syrus/runs/40" →
  #          "-syrus-home-.syrus-runs-40"
  def self.canonical_path_for(home:, cwd:, session_id:)
    encoded = cwd.to_s.gsub("/", "-")
    File.join(home, ".claude", "projects", encoded, "#{session_id}.jsonl")
  end
end
