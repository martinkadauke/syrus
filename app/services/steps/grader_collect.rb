module Steps
  # Iteration-decision Step. Runs after all per-grader Steps in the
  # loop iteration have completed (succeeded OR failed — graders
  # don't short-circuit each other; they all run regardless). If any
  # *required* grader Step in this iteration ended in `:failed`,
  # this Step raises StepFailed, which the dispatcher recognizes as
  # the loop's iteration signal (see StepDispatcher#fail! handling
  # for grader_collect kind). Otherwise it succeeds and the chain
  # advances past the loop.
  #
  # Aggregating the iteration's results into a single artifact is a
  # convenience for Prompts::GradeFailureFeedback (Phase C) — the
  # prompt can iterate this rollup instead of walking the chain
  # manually. The Step#details on each grader Step remains the
  # source of truth.
  class GraderCollect < Base
    def call
      grader_steps = current_iteration_graders
      append_iteration_results!(grader_steps)

      failed_required = grader_steps.select do |g|
        g.details && g.details["required"] && g.state == "failed"
      end

      if failed_required.empty?
        log("[grader_collect] all required graders passed (#{grader_steps.size} grader Step(s) ran)")
        return
      end

      failed_names = failed_required.map { |g| g.details["name"] }.join(", ")
      log("[grader_collect] required graders failed: #{failed_names}")
      raise Base::StepFailed, "required graders failed: #{failed_names}"
    end

    private

    # Grader Steps belonging to this loop iteration, in chain order.
    # We scope by loop_id + iteration to avoid picking up siblings
    # from a different iteration (when multiple loop iterations
    # have been materialized).
    def current_iteration_graders
      return [] if step.loop_id.blank?

      workflow.steps
              .where(kind: "grader", loop_id: step.loop_id, iteration: step.iteration)
              .order(:position)
              .to_a
    end

    # Convenience rollup onto workflow.artifacts["iterations"] for
    # later UI / prompt consumers. Mirrors the structure that
    # Steps::Grade wrote per iteration so existing
    # Prompts::GradeFailureFeedback rendering still works during the
    # transitional period.
    def append_iteration_results!(grader_steps)
      iterations = Array(workflow.artifact("iterations"))
      index = run.iteration - 1
      iterations[index] = grader_steps.map do |g|
        details = g.details || {}
        {
          "name" => details["name"],
          "required" => details["required"],
          "status" => g.state == "succeeded" ? "passed" : "failed",
          "exit_code" => details["exit_code"],
          "duration_s" => details["duration_s"],
          "log_path" => details["log_path"],
          "log_bytes" => details["log_bytes"],
          "output" => details["output"]
        }
      end
      workflow.set_artifact!("iterations", iterations)
    end
  end
end
