# Walkthrough videos are 100-500MB each and live in the syrus-data volume
# (Active Storage: local_volume on SQLite hosts, minio otherwise). Without a
# sweep they accumulate forever — a handful of users recording daily would
# fill the PVC. The analysis JSON is what has lasting value; the video is a
# means to it, useful only for a retry (which re-uploads to Gemini anyway,
# since Gemini's own copy expires after 48h).
#
# Policy: keep the blob for a short retry window after the row settles, then
# purge the ATTACHMENT while keeping the row + analysis. A walkthrough older
# than the window can no longer be retried, which for a week-old recording is
# the right trade. Runs daily on `default`.
class VideoWalkthroughPruneJob < ApplicationJob
  queue_as :default

  # Long enough that "it failed, let me retry tomorrow" works; short enough
  # that videos don't pile up. Gemini's 48h file retention already means a
  # retry past two days re-uploads from our blob, so the blob is the only
  # thing enabling retry — 7 days is a generous ceiling on that.
  RETAIN_BLOB = 7.days

  def perform
    cutoff = RETAIN_BLOB.ago
    purged = 0

    ChatVideoWalkthrough.where(state: %w[analyzed failed])
                        .where("updated_at < ?", cutoff)
                        .find_each do |walkthrough|
      next unless walkthrough.file.attached?

      walkthrough.file.purge_later
      purged += 1
    end

    Rails.logger.info("[VideoWalkthroughPruneJob] purged #{purged} walkthrough video blob(s) older than #{RETAIN_BLOB.inspect}") if purged.positive?
  end
end
