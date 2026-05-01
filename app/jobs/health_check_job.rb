class HealthCheckJob < ApplicationJob
  queue_as :default

  def perform(message = "alive")
    Rails.logger.info("[HealthCheckJob] #{message} at #{Time.current.iso8601}")
  end
end
