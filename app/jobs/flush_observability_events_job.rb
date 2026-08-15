class FlushObservabilityEventsJob < ApplicationJob
  queue_as :low_priority_maintenance

  def perform
    Observability::EventSink.flush!
    PerformanceLogEvent.expired.delete_all
    WorkflowActivityEvent.expired.delete_all
  end
end
