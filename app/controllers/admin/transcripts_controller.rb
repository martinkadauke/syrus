module Admin
  # Raw JSONL transcript downloads for offline analysis (jq grep, etc.).
  # The navigable transcript UI is rendered by React from the app API.
  class TranscriptsController < BaseController
    def download
      @run = Run.find(params[:run_id])
      session = @run.provider_session

      unless session
        redirect_back fallback_location: job_path(@run.job),
                      alert: "No agent session captured for Run ##{@run.id}."
        return
      end

      send_data session.transcript_jsonl,
                filename: "run-#{@run.id}-#{session.session_id}.jsonl",
                type: "application/jsonl"
    end
  end
end
