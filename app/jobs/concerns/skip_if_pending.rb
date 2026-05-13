module SkipIfPending
  extend ActiveSupport::Concern

  class_methods do
    def perform_later(*args, **kwargs)
      return super if args.any? || kwargs.any?
      return if SolidQueue::Job.where(class_name: name, finished_at: nil).exists?
      super
    end
  end
end
