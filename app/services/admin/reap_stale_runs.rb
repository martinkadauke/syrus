module Admin
  class ReapStaleRuns
    Result = Data.define(:message, :issues_count, :repairs_count)

    def self.call(source:)
      if Feature.unified_work_engine_reconciler_enabled?
        result = WorkEngine::Reconciler.call(
          source: source,
          execute_repairs: true
        )
        Result.new(
          message: "WorkEngine reconciler ran inline.",
          issues_count: result.issues.size,
          repairs_count: result.repair_executions.size
        )
      else
        ReapStaleRunsJob.perform_now
        Result.new(
          message: "ReapStaleRunsJob ran inline.",
          issues_count: nil,
          repairs_count: nil
        )
      end
    end
  end
end
