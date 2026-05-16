require "rails_helper"

# Per-chip smoke tests. The Compiler is exercised via the public
# Filters::Compiler.call entry — these specs lean on it rather than
# instantiating chip classes directly so the AST round-trip is part
# of the coverage.
RSpec.describe "Filters::Chips" do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  def run(field:, op:, value:)
    Filters::Compiler.call(
      Filters::Ast.parse("field" => field, "op" => op, "value" => value),
      scope: Job.all,
      user: user
    )
  end

  describe "state" do
    it "filters by exact state" do
      open_job = Factories.job(repository: repo, issue_number: 1)
      closed_job = Factories.job(repository: repo, issue_number: 2)
      closed_job.close!; closed_job.save!

      expect(run(field: "state", op: "is", value: "open")).to contain_exactly(open_job)
    end

    it "supports is_one_of for multi-value matches" do
      open_job = Factories.job(repository: repo, issue_number: 1)
      closed_job = Factories.job(repository: repo, issue_number: 2)
      closed_job.close!; closed_job.save!

      expect(run(field: "state", op: "is_one_of", value: %w[ open closed ])).to contain_exactly(open_job, closed_job)
    end
  end

  describe "repository_id" do
    it "filters to one repository" do
      api = Factories.repository(user: user, owner: "acme", name: "api")
      mine = Factories.job(repository: repo, issue_number: 1)
      Factories.job(repository: api, issue_number: 2)

      expect(run(field: "repository_id", op: "is", value: repo.id)).to contain_exactly(mine)
    end
  end

  describe "pr_present" do
    it "matches jobs with a PR when value is 'has'" do
      with_pr = Factories.job(repository: repo, issue_number: 1, pr_number: 42)
      Factories.job(repository: repo, issue_number: 2)

      expect(run(field: "pr_present", op: "is", value: "has")).to contain_exactly(with_pr)
    end

    it "matches jobs without a PR when value is 'none'" do
      Factories.job(repository: repo, issue_number: 1, pr_number: 42)
      without = Factories.job(repository: repo, issue_number: 2)

      expect(run(field: "pr_present", op: "is", value: "none")).to contain_exactly(without)
    end
  end

  describe "age" do
    it "filters by created_at within the named window" do
      fresh = Factories.job(repository: repo, issue_number: 1)
      old = Factories.job(repository: repo, issue_number: 2)
      old.update!(created_at: 30.days.ago)

      expect(run(field: "age", op: "is", value: "1d")).to contain_exactly(fresh)
    end
  end

  describe "tags" do
    let(:bug) { Factories.tag(user: user, name: "bug") }
    let(:epic) { Factories.tag(user: user, name: "epic") }

    it "contains_any returns jobs with at least one of the tags" do
      tagged = Factories.job(repository: repo, issue_number: 1)
      tagged.tags << bug
      Factories.job(repository: repo, issue_number: 2)

      expect(run(field: "tags", op: "contains_any", value: [ bug.id ])).to contain_exactly(tagged)
    end

    it "contains_all only matches jobs with every listed tag" do
      both = Factories.job(repository: repo, issue_number: 1)
      both.tags << bug
      both.tags << epic
      one = Factories.job(repository: repo, issue_number: 2)
      one.tags << bug

      expect(run(field: "tags", op: "contains_all", value: [ bug.id, epic.id ])).to contain_exactly(both)
    end

    it "contains_none excludes jobs that have any of the listed tags" do
      tagged = Factories.job(repository: repo, issue_number: 1)
      tagged.tags << bug
      untagged = Factories.job(repository: repo, issue_number: 2)

      expect(run(field: "tags", op: "contains_none", value: [ bug.id ])).to contain_exactly(untagged)
    end
  end

  describe "attention preset" do
    it "pinned: returns only jobs pinned by the operator" do
      pinned = Factories.job(repository: repo, issue_number: 1)
      Factories.job(repository: repo, issue_number: 2)
      Factories.job_pin(user: user, job: pinned)

      expect(run(field: "attention", op: "is", value: "pinned")).to contain_exactly(pinned)
    end

    it "just_failed: returns jobs whose latest run is failed" do
      failed = Factories.job(repository: repo, issue_number: 1)
      failed.initial_run.update!(state: "failed", finished_at: Time.current)
      Factories.job(repository: repo, issue_number: 2)

      expect(run(field: "attention", op: "is", value: "just_failed")).to contain_exactly(failed)
    end

    it "merged_this_week: returns recently-merged closed threads" do
      merged = Factories.job(repository: repo, issue_number: 1)
      merged.update!(state: "closed", closure_reason: "pr_merged", finished_at: 2.days.ago)
      Factories.job(repository: repo, issue_number: 2)

      expect(run(field: "attention", op: "is", value: "merged_this_week")).to contain_exactly(merged)
    end
  end
end
