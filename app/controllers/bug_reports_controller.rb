class BugReportsController < ApplicationController
  def create
    result = BugReports::Creator.new(user: Current.user).call(
      title: params[:title],
      description: params[:description],
      screenshot: params[:screenshot]
    )
    unless result.success?
      report_failure(result.error)
      return
    end

    respond_to do |format|
      format.html { redirect_back fallback_location: legacy_dashboard_jobs_path, notice: "Bug report queued." }
      format.json { render json: { message: "Bug report queued.", job_id: result.job.id }, status: :created }
    end
  end

  private

  def report_failure(message)
    respond_to do |format|
      format.html { redirect_back fallback_location: legacy_dashboard_jobs_path, alert: message }
      format.json { render json: { error: message }, status: :unprocessable_entity }
    end
  end
end
