module ScheduledTasksHelper
  STATE_STYLES = {
    "scheduled"   => "bg-green-100 text-green-700",
    "paused"      => "bg-gray-100 text-gray-600",
    "auto_paused" => "bg-red-100 text-red-700",
    "fired"       => "bg-blue-100 text-blue-700"
  }.freeze

  def scheduled_task_state_pill(task)
    colored_pill(task.state, classes: STATE_STYLES[task.state] || ApplicationHelper::PILL_FALLBACK_CLASSES)
  end
end
