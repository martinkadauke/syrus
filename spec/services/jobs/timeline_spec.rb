require "rails_helper"

RSpec.describe Jobs::Timeline do
  let(:job) { Factories.job }

  def kinds_of(events) = events.map(&:kind)
  def titles_of(events) = events.map(&:title)
  def sources_of(events) = events.map(&:source)

  describe ".for" do
    it "returns chronologically-sorted events derived from workflow + step + run timestamps" do
      # job factory created an Initial workflow with prepare / implement /
      # summarize / pr_open steps + the first step's queued initial Run.
      wf = job.workflows.last
      implement = wf.steps.find_by(kind: "implement")
      run = implement.runs.first || implement.runs.create!(job: job, trigger_kind: wf.trigger_kind)

      # Timestamps must increase monotonically so the sort is deterministic.
      base = Time.zone.local(2026, 5, 4, 12, 0, 0)
      wf.update_columns(created_at: base, started_at: base + 1.second)
      implement.update_columns(started_at: base + 2.seconds)
      run.update_columns(created_at: base + 1.second,
                         started_at: base + 3.seconds,
                         finished_at: base + 4.seconds,
                         state: "succeeded",
                         agent_outcome: "success",
                         agent_turns: 5)
      implement.update_columns(finished_at: base + 4.seconds, state: "succeeded")
      wf.update_columns(finished_at: base + 5.seconds, state: "succeeded")

      events = described_class.for(job)

      # Every timestamp produces an event; chronological order.
      timestamps = events.map(&:at).compact
      expect(timestamps).to eq(timestamps.sort)

      # All three sources are represented.
      expect(sources_of(events)).to include("workflow", "step", "run")

      # Lifecycle markers present.
      titles = titles_of(events).join(" | ")
      expect(titles).to include("Workflow ##{wf.id} (initial) created")
      expect(titles).to include("Workflow ##{wf.id} started")
      expect(titles).to include("Workflow ##{wf.id} succeeded")
      expect(titles).to include("Step implement started")
      expect(titles).to include("Step implement succeeded")
      expect(titles).to include("Run ##{run.id} created (initial)")
      expect(titles).to include("Run ##{run.id} started")
      expect(titles).to include("Run ##{run.id} succeeded")
    end

    it "kinds reflect terminal state (success/failure/cancel)" do
      wf = job.workflows.last
      step = wf.steps.find_by(kind: "implement")
      run  = step.runs.first || step.runs.create!(job: job, trigger_kind: wf.trigger_kind)

      run.update_columns(state: "failed",
                         started_at: 1.minute.ago, finished_at: Time.current,
                         agent_outcome: "error_max_turns")
      step.update_columns(state: "failed",
                          started_at: 1.minute.ago, finished_at: Time.current)
      wf.update_columns(state: "failed",
                        started_at: 1.minute.ago, finished_at: Time.current)

      events = described_class.for(job)
      failure_titles = events.select { |e| e.kind == :failure }.map(&:title)
      expect(failure_titles).to include("Workflow ##{wf.id} failed",
                                       "Step implement failed",
                                       "Run ##{run.id} failed")
    end

    it "includes outcome + turns + duration in run finish detail" do
      wf = job.workflows.last
      run = wf.first_step.runs.first
      run.update_columns(state: "succeeded",
                         started_at: 90.seconds.ago, finished_at: Time.current,
                         agent_outcome: "success",
                         agent_turns: 12)

      events = described_class.for(job)
      finish_event = events.find { |e| e.title == "Run ##{run.id} succeeded" }
      expect(finish_event.detail).to include("outcome=success")
      expect(finish_event.detail).to include("turns=12")
      expect(finish_event.detail).to include("duration 1m30s")
    end

    it "doesn't blow up on records that never started or finished" do
      # job factory leaves the initial Run in `queued` (no
      # started_at, no finished_at). Timeline still works.
      events = described_class.for(job)
      expect(events).not_to be_empty
      expect(events.first.title).to match(/created/)
    end

    it "includes the Run id in event refs for drill-downs" do
      run = job.initial_run
      events = described_class.for(job)
      run_event = events.find { |e| e.source == "run" }
      expect(run_event.ref[:run_id]).to eq(run.id)
      expect(run_event.ref[:workflow_id]).to be_present
      expect(run_event.ref[:step_id]).to be_present
    end
  end
end
