module Admin
  # Dedicated /admin/stuck list — same items the overview's tile
  # links to, with richer per-item context (Step kind, age,
  # workflow trigger, drill-down links to transcript + job).
  # Source of truth is Admin::StuckItems so the two views can't
  # drift.
  class StuckController < BaseController
    POLL_INTERVAL_SECONDS = 30

    def index
      @poll_interval = POLL_INTERVAL_SECONDS
      @items = StuckItems.all
      @any_alarm = @items.any? { |i| i.severity == :alarm }
    end
  end
end
