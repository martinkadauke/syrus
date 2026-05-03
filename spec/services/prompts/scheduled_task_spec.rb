require "rails_helper"

RSpec.describe Prompts::ScheduledTask do
  let(:user) { Factories.user }
  let(:repository) { Factories.repository(user: user, owner: "acme", name: "widgets", default_branch: "main") }
  let(:task) do
    ScheduledTask.create!(
      user: user, repository: repository,
      name: "Sweep dead code",
      prompt: "Look for dead code in `#{'{{repo_slug}}'}` and remove anything orphaned. Today is {{date}}.",
      kind: "cron", cron_expression: "0 9 * * 1", pr_pileup_policy: "skip"
    )
  end
  let(:fired_at) { Time.utc(2026, 5, 4, 9, 23, 0) }

  it "wraps the user prompt in a Syrus preamble that warns against making work" do
    output = described_class.new(scheduled_task: task, fired_at: fired_at).to_s
    expect(output).to include("scheduled maintenance task")
    expect(output).to match(/only commit changes if there's something\s+genuinely\s+worth changing/i)
    expect(output).to match(/run\s+`submit_summary`/)
    expect(output).to include(repository.slug)
  end

  it "appends the SubmitSummaryInstructions block" do
    output = described_class.new(scheduled_task: task, fired_at: fired_at).to_s
    expect(output).to include("submit_summary")
    expect(output).to include("pr_title")
  end

  it "interpolates supported template variables in the user prompt" do
    output = described_class.new(scheduled_task: task, fired_at: fired_at).to_s
    expect(output).to include("acme/widgets")
    expect(output).to include("Today is 2026-05-04")
  end

  it "leaves unknown variables literal" do
    task.update!(prompt: "{{not_a_real_var}} stays as-is.")
    output = described_class.new(scheduled_task: task, fired_at: fired_at).to_s
    expect(output).to include("{{not_a_real_var}}")
  end

  it "renders 'never' when last_fired_at is nil" do
    task.update!(prompt: "Last fire: {{last_fired_at}}.")
    output = described_class.new(scheduled_task: task, fired_at: fired_at).to_s
    expect(output).to include("Last fire: never.")
  end

  it "uses the iso8601 of last_fired_at when present" do
    last = Time.utc(2026, 4, 27, 9, 23, 0)
    task.update!(prompt: "Last fire: {{last_fired_at}}.", last_fired_at: last)
    output = described_class.new(scheduled_task: task, fired_at: fired_at).to_s
    expect(output).to include(last.iso8601)
  end
end
