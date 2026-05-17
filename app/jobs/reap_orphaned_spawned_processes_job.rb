# Finalize SpawnedProcess rows that never got their `finished_at`
# stamp — usually because the worker pod crashed mid-stream and the
# Ruby ensure path didn't run. Worker pods on a given hostname own
# rows tagged with that hostname; only the local worker can verify
# pid aliveness, so the reap runs hostname-scoped: each pod cleans
# up its own ghosts.
#
# Without this, the admin UI would show running rows indefinitely.
require "socket"

class ReapOrphanedSpawnedProcessesJob < ApplicationJob
  include SkipIfPending

  queue_as :default

  # If a process row hasn't been heartbeated in this long AND the
  # process is no longer in /proc, finalize it as "orphaned".
  STALE_THRESHOLD = 10.minutes

  def perform
    hostname = Socket.gethostname
    cutoff = STALE_THRESHOLD.ago

    SpawnedProcess.running
      .where(hostname: hostname)
      .where("(last_chunk_at IS NULL AND started_at < :t) OR last_chunk_at < :t", t: cutoff)
      .find_each do |sp|
        next if pid_alive?(sp.pid)

        sp.update!(finished_at: Time.current, outcome: "orphaned")
        Rails.logger.info("[ReapOrphanedSpawnedProcessesJob] finalized stale SpawnedProcess ##{sp.id} (pid #{sp.pid}, kind #{sp.kind})")
      end
  end

  private

  def pid_alive?(pid)
    return false unless pid

    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    # Can't signal but the pid exists in /proc — leave it; another
    # tick will catch it if it actually dies. Better than false-
    # finalizing a live process.
    true
  end
end
