module Api
  module V1
    module App
      class JobsController < BaseController
        def show
          render json: ::App::JobDetailPayload.build(job: find_job, user: Current.user)
        end

        def timeline
          render json: ::App::JobDetailPayload.timeline(job: find_job)
        end

        private

        def find_job
          Current.user.jobs
                      .includes(
                        :repository,
                        :tags,
                        job_attachments: { file_attachment: :blob },
                        dependencies: [ :created_by_user, depends_on_job: :repository ],
                        dependent_links: [ job: :repository ],
                        workflows: { steps: { runs: [ :claude_session, :run_diagnostic, :run_health_snapshots, :job_logs ] } },
                        runs: [ :job_logs, :run_health_snapshots, :claude_session, :run_diagnostic ]
                      )
                      .find(params[:id])
        end
      end
    end
  end
end
