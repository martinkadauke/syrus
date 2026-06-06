module App
  class WorkflowNavigation
    include Rails.application.routes.url_helpers

    PER_PAGE = 10

    def self.path(workflow, per_page: PER_PAGE)
      new(workflow: workflow, per_page: per_page).path
    end

    def initialize(workflow:, per_page: PER_PAGE)
      @workflow = workflow
      @per_page = per_page
    end

    def path
      "#{job_path(workflow.job)}?#{query.to_query}#workflow-#{workflow.id}"
    end

    private

    attr_reader :workflow, :per_page

    def query
      query = { tab: "workflows" }
      query[:workflows_page] = page if page > 1
      query
    end

    def page
      ((preceding_workflows_count / per_page) + 1).to_i
    end

    def preceding_workflows_count
      workflow.job.workflows
              .where("created_at > :created_at OR (created_at = :created_at AND id > :id)",
                     created_at: workflow.created_at,
                     id: workflow.id)
              .count
    end
  end
end
