require "rails_helper"

RSpec.describe PollScheduledTasksJob do
  let(:user) { Factories.user }
  let(:repository) { Factories.repository(user: user) }

  def cron_task(**overrides)
    ScheduledTask.create!({
      user: user, repository: repository,
      name: "T", prompt: "p",
      kind: "cron", cron_expression: "0 * * * *",
      pr_pileup_policy: "skip"
    }.merge(overrides))
  end

  it "fires due tasks via ScheduledTaskFire" do
    task = cron_task
    task.update_columns(last_fired_at: 2.hours.ago)

    expect_any_instance_of(ScheduledTaskFire).to receive(:call)
      .and_return(ScheduledTaskFire::Result.new(job: nil, skipped: false, reason: nil))

    described_class.perform_now
  end

  it "leaves not-yet-due tasks alone" do
    task = cron_task
    task.update_columns(last_fired_at: 1.minute.ago)

    expect_any_instance_of(ScheduledTaskFire).not_to receive(:call)
    described_class.perform_now
  end

  it "skips paused tasks" do
    task = cron_task
    task.update_columns(last_fired_at: 2.hours.ago)
    task.pause!

    expect_any_instance_of(ScheduledTaskFire).not_to receive(:call)
    described_class.perform_now
  end

  it "skips archived tasks" do
    task = cron_task
    task.update_columns(last_fired_at: 2.hours.ago)
    task.soft_delete!

    expect_any_instance_of(ScheduledTaskFire).not_to receive(:call)
    described_class.perform_now
  end

  it "isolates one bad task's failure from the rest of the pass" do
    bad  = cron_task(name: "bad")
    good = cron_task(name: "good")
    bad.update_columns(last_fired_at: 2.hours.ago)
    good.update_columns(last_fired_at: 2.hours.ago)

    call_count = 0
    allow_any_instance_of(ScheduledTaskFire).to receive(:call) do
      call_count += 1
      raise "boom" if call_count == 1
      ScheduledTaskFire::Result.new(job: nil, skipped: false, reason: nil)
    end

    expect { described_class.perform_now }.not_to raise_error
    expect(call_count).to eq(2)  # both tasks attempted
  end
end
