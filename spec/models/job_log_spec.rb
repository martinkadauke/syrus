require "rails_helper"

RSpec.describe JobLog do
  let(:job) { Factories.job }

  it "appends chunks ordered by sequence" do
    JobLog.create!(job: job, chunk: "second", sequence: 1)
    JobLog.create!(job: job, chunk: "first",  sequence: 0)
    expect(job.reload.job_logs.map(&:chunk)).to eq(%w[first second])
  end

  it "rejects update — append-only" do
    log = JobLog.create!(job: job, chunk: "hello", sequence: 0)
    expect { log.update!(chunk: "rewritten") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "rejects direct destroy — append-only" do
    log = JobLog.create!(job: job, chunk: "hello", sequence: 0)
    expect { log.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "permits cascading destroy when parent Job goes away" do
    JobLog.create!(job: job, chunk: "hello", sequence: 0)
    expect { job.destroy! }.not_to raise_error
    expect(JobLog.where(job_id: job.id).count).to eq(0)
  end

  it "enforces unique sequence per job" do
    JobLog.create!(job: job, chunk: "a", sequence: 0)
    dup = JobLog.new(job: job, chunk: "b", sequence: 0)
    expect(dup).not_to be_valid
  end
end
