module Api
  module V1
    module Admin
      # Mirror of Admin::OverviewController + Admin::StuckController.
      # Same data assembly (most of it just reads counts off Run /
      # Workflow / SolidQueue tables); both UI and API render from
      # the same Admin::StuckItems source for the watchlist so the
      # two surfaces can't drift.
      #
      #   GET /api/v1/admin/overview → tile-shaped rollup
      #   GET /api/v1/admin/stuck    → full StuckItems list
      class OverviewController < BaseController
        def show
          render json: ::Admin::OverviewPayload.new.as_json
        end

        def stuck
          render json: ::Admin::OverviewPayload.new.stuck_json
        end
      end
    end
  end
end
