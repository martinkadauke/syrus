module EnqueuesSearchIndex
  extend ActiveSupport::Concern

  private

  def enqueue_search_index_job(job_class, *args)
    job_class.perform_later(*args)
  rescue SolidQueue::Job::EnqueueError, ActiveRecord::StatementInvalid => e
    Rails.logger.warn(
      "[SearchIndex] skipped #{job_class.name} for #{self.class.name}##{id}: #{e.class}: #{e.message}"
    )
  end
end
