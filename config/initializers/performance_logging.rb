ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, started, finished, _id, payload|
  PerformanceLogging.record_sql(payload, (finished - started) * 1_000.0)
end

ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, started, finished, _id, payload|
  PerformanceLogging.record_request(payload, (finished - started) * 1_000.0)
end
