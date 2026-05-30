module Admin
  # Legacy /admin/stuck/legacy list — same items the overview's tile
  # links to in the React route, with the original ERB auto-refresh
  # page kept as a fallback during the SPA migration.
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
