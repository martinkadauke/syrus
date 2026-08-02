class PlatformPollingJob < ApplicationJob
  queue_as :default

  @registry = []

  class << self
    def registry
      @registry
    end

    def inherited(subclass)
      super
      @registry << subclass
    end

    # Enqueue configured registered subclasses that are not already running.
    # Tolerates missing SolidQueue tables (non-server environments).
    def start_all!
      registry.filter_map { |klass| start_one(klass) }
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => e
      Rails.logger.warn("PlatformPollingJob.start_all! skipped: #{e.message}")
      []
    end

    def start_one(klass)
      return unless klass.new.send(:configured?)
      return if SolidQueue::Job.where(class_name: klass.name, finished_at: nil).exists?

      klass.perform_later
      klass.name
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => e
      Rails.logger.warn("PlatformPollingJob.start_one skipped for #{klass.name}: #{e.message}")
      nil
    end
  end

  def perform
    return unless configured?
    return if duplicate_running?
    poll_once
  rescue => e
    Rails.logger.error("#{self.class}: #{e}")
  ensure
    self.class.perform_later if configured?
  end

  private

  def configured? = raise NotImplementedError
  def poll_once   = raise NotImplementedError

  def duplicate_running?
    SolidQueue::Job
      .where(class_name: self.class.name, finished_at: nil)
      .count > 1
  rescue ActiveRecord::StatementInvalid
    false
  end
end
