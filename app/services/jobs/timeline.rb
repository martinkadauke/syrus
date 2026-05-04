module Jobs
  # Builds a flat, chronological event list from the timestamps
  # that already live on a Job's workflows, steps, and runs.
  # Replaces the "scroll between three tables to reconstruct
  # what happened" pattern that recurred across recent debug
  # sessions.
  #
  # No new schema — every event is derived from records that
  # already track created_at / started_at / finished_at /
  # state. PR-side events (PR opened, comments received,
  # mergeability flips) need a proper audit log to surface
  # cleanly; out of scope for v1.
  #
  # Each event is a Data with:
  #   :at     — Time
  #   :kind   — :info | :start | :success | :failure | :cancel
  #   :source — "workflow" | "step" | "run"
  #   :title  — short human description
  #   :detail — optional secondary text
  #   :ref    — { workflow_id:, step_id:, run_id: } for drill-down
  class Timeline
    Event = Data.define(:at, :kind, :source, :title, :detail, :ref)

    def self.for(job)
      new(job).events
    end

    def initialize(job)
      @job = job
    end

    def events
      events = []

      @job.workflows.includes(steps: :runs).each do |wf|
        events.concat(workflow_events(wf))
        wf.steps.each do |step|
          events.concat(step_events(step))
          step.runs.each do |run|
            events.concat(run_events(run))
          end
        end
      end

      # Stable sort: chronological with NULLs last (records that
      # never started/finished still surface, just not in the
      # main timeline order).
      events.compact.sort_by { |e| e.at || Time.zone.at(0) }
    end

    private

    def workflow_events(wf)
      label = "Workflow ##{wf.id}"
      label_with_kind = "#{label} (#{wf.trigger_kind})"
      ref = { workflow_id: wf.id }

      [
        Event.new(at: wf.created_at, kind: :info, source: "workflow",
                  title: "#{label_with_kind} created", detail: nil, ref: ref),
        wf.started_at && Event.new(
          at: wf.started_at, kind: :start, source: "workflow",
          title: "#{label} started", detail: nil, ref: ref
        ),
        wf.finished_at && Event.new(
          at: wf.finished_at,
          kind: terminal_kind(wf.state),
          source: "workflow",
          title: "#{label} #{wf.state}",
          detail: workflow_finish_detail(wf),
          ref: ref
        )
      ]
    end

    def step_events(step)
      label = "Step #{step.kind}"
      ref = { workflow_id: step.workflow_id, step_id: step.id }

      [
        step.started_at && Event.new(
          at: step.started_at, kind: :start, source: "step",
          title: "#{label} started", detail: nil, ref: ref
        ),
        step.finished_at && Event.new(
          at: step.finished_at,
          kind: terminal_kind(step.state),
          source: "step",
          title: "#{label} #{step.state}",
          detail: step_finish_detail(step),
          ref: ref
        )
      ]
    end

    def run_events(run)
      label = "Run ##{run.id}"
      ref = { workflow_id: run.step&.workflow_id, step_id: run.step_id, run_id: run.id }

      [
        Event.new(at: run.created_at, kind: :info, source: "run",
                  title: "#{label} created (#{run.trigger_kind})",
                  detail: nil, ref: ref),
        run.started_at && Event.new(
          at: run.started_at, kind: :start, source: "run",
          title: "#{label} started", detail: nil, ref: ref
        ),
        run.finished_at && Event.new(
          at: run.finished_at,
          kind: terminal_kind(run.state),
          source: "run",
          title: "#{label} #{run.state}",
          detail: run_finish_detail(run),
          ref: ref
        )
      ]
    end

    def terminal_kind(state)
      case state
      when "succeeded" then :success
      when "failed"    then :failure
      when "cancelled" then :cancel
      else                  :info
      end
    end

    def workflow_finish_detail(wf)
      bits = []
      bits << "duration #{format_duration(wf.started_at, wf.finished_at)}" if wf.started_at
      bits.join(" · ").presence
    end

    def step_finish_detail(step)
      bits = []
      bits << "duration #{format_duration(step.started_at, step.finished_at)}" if step.started_at
      bits.join(" · ").presence
    end

    def run_finish_detail(run)
      bits = []
      bits << "outcome=#{run.agent_outcome}" if run.agent_outcome.present?
      bits << "turns=#{run.agent_turns}"    if run.agent_turns
      bits << "duration #{format_duration(run.started_at, run.finished_at)}" if run.started_at
      bits.join(" · ").presence
    end

    def format_duration(start, finish)
      seconds = (finish - start).to_i
      return "#{seconds}s" if seconds < 60
      mins = seconds / 60
      "#{mins}m#{(seconds % 60).to_s.rjust(2, '0')}s"
    end
  end
end
