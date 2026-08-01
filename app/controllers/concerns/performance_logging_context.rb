module PerformanceLoggingContext
  extend ActiveSupport::Concern

  included do
    around_action :with_performance_logging_context
    before_action :refresh_performance_logging_user_context
  end

  private

  def with_performance_logging_context(&action)
    PerformanceLogging.with_request_context(
      request_id: request.request_id,
      method: request.request_method,
      path: request.fullpath,
      controller: self.class.name,
      action: action_name,
      user_id: performance_logging_user_id,
      admin: performance_logging_admin?
    ) do
      action.call
    end
  end

  def performance_logging_user_id
    Current.user&.id
  end

  def performance_logging_admin?
    Current.user&.admin?
  end

  def refresh_performance_logging_user_context
    PerformanceLogging.merge_request_context(
      controller: self.class.name,
      action: action_name,
      user_id: performance_logging_user_id,
      admin: performance_logging_admin?
    )
  end
end
