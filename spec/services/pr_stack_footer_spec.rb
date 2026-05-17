require "rails_helper"

RSpec.describe PrStackFooter do
  let(:repository) { Factories.repository(owner: "acme", name: "widgets") }
  # job_record creates without firing advance_after_triage!, so the
  # parent_job_id assignment survives. Factories.job advances through
  # triaging, which runs JobStackResolver and clears parent_job when
  # there's no matching JobDependency — the stack-footer specs only
  # need the model relation, not the dependency machinery.
  let(:parent) { Factories.job_record(repository: repository, issue_number: 41, pr_number: 123) }
  let(:job) { Factories.job_record(repository: repository, issue_number: 42, pr_number: 124, parent_job: parent) }
  let!(:child) { Factories.job_record(repository: repository, issue_number: 43, pr_number: 125, parent_job: job) }

  it "renders a linked stack footer with the current PR highlighted" do
    body = described_class.apply("Body", job)

    expect(body).to include(described_class::START_MARKER)
    expect(body).to include("[#123](https://github.com/acme/widgets/pull/123)")
    expect(body).to include("**[this](https://github.com/acme/widgets/pull/124)**")
    expect(body).to include("[#125](https://github.com/acme/widgets/pull/125)")
  end

  it "replaces the managed footer without touching body text" do
    first = described_class.apply("Agent body", job)
    child.update!(pr_number: 126)

    body = described_class.apply(first, job)

    expect(body).to start_with("Agent body")
    expect(body.scan(described_class::START_MARKER).size).to eq(1)
    expect(body).to include("pull/126")
    expect(body).not_to include("pull/125")
  end

  it "omits the footer for unstacked PRs and strips an obsolete footer" do
    solo = Factories.job(repository: repository, issue_number: 44, pr_number: 126)
    existing = [
      "Body",
      described_class::START_MARKER,
      "**Stack:** stale",
      described_class::END_MARKER
    ].join("\n")

    expect(described_class.apply(existing, solo)).to eq("Body")
  end
end
