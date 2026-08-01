require "rails_helper"

RSpec.describe ProviderQuotaReset do
  let(:now) { Time.zone.parse("2026-08-01 14:00:00 UTC") }
  let(:job) { Factories.job(agent_provider: "claude") }
  let(:workflow) { job.latest_workflow }
  let(:run) { workflow.first_step.runs.first }

  it "parses Claude reset times with an explicit timezone from the failure time" do
    run.update!(agent_provider: "claude", finished_at: Time.zone.parse("2026-08-01 08:30:00 UTC"))
    RunDiagnostic.create!(
      run: run,
      error_class: "Steps::Base::StepFailed",
      error_message: "You're out of extra usage · resets 7am (America/New_York)"
    )

    retry_after = described_class.retry_after_for_run(run, now: now)

    expect(retry_after).to eq(Time.find_zone("America/New_York").parse("2026-08-01 07:05:00"))
  end

  it "uses the next matching time when reset text is earlier than the failure time" do
    run.update!(agent_provider: "claude", finished_at: Time.zone.parse("2026-08-01 18:00:00 UTC"))
    RunDiagnostic.create!(
      run: run,
      error_class: "Steps::Base::StepFailed",
      error_message: "Claude API error: usage limit reached, resets at 1pm"
    )

    retry_after = described_class.retry_after_for_run(run, now: now)

    expect(retry_after).to eq(Time.zone.parse("2026-08-02 13:05:00"))
  end

  it "prefers Codex structured usage reset windows over log text" do
    reset_at = Time.zone.parse("2026-08-01 15:30:00 UTC")
    job.user.update!(
      codex_usage_status: "exhausted",
      codex_usage_observed_at: now,
      codex_usage_snapshot: {
        "primary" => {
          "remaining_percent" => 0.0,
          "reset_at" => reset_at.iso8601
        },
        "rate_limit_reached_type" => "rate_limit_reached"
      }
    )
    run.update!(agent_provider: "codex", finished_at: Time.zone.parse("2026-08-01 13:00:00 UTC"))
    RunDiagnostic.create!(
      run: run,
      error_class: "Steps::Base::StepFailed",
      error_message: "resets at 11pm"
    )

    expect(described_class.retry_after_for_run(run, now: now)).to eq(reset_at + 5.minutes)
  end

  it "chooses the exhausted Codex window rather than the earliest non-exhausted reset" do
    five_hour_reset = Time.zone.parse("2026-08-01 15:00:00 UTC")
    weekly_reset = Time.zone.parse("2026-08-03 12:00:00 UTC")
    job.user.update!(
      codex_usage_status: "exhausted",
      codex_usage_observed_at: now,
      codex_usage_snapshot: {
        "primary" => {
          "label" => "weekly usage",
          "remaining_percent" => 0.0,
          "reset_at" => weekly_reset.iso8601
        },
        "secondary" => {
          "label" => "5 hour usage",
          "remaining_percent" => 50.0,
          "reset_at" => five_hour_reset.iso8601
        },
        "rate_limit_reached_type" => "rate_limit_reached"
      }
    )
    run.update!(agent_provider: "codex", finished_at: Time.zone.parse("2026-08-01 13:00:00 UTC"))

    expect(described_class.retry_after_for_run(run, now: now)).to eq(weekly_reset + 5.minutes)
  end
end
