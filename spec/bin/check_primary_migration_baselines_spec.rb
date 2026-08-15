# frozen_string_literal: true

require "open3"
require "rails_helper"

RSpec.describe "bin/check-primary-migration-baselines", :ci_only do
  let(:root) { Rails.root.to_s }
  let(:script) { File.join(root, "bin/check-primary-migration-baselines") }

  def run_check(baseline_tags)
    env = {
      "BUNDLE_APP_CONFIG" => ENV["BUNDLE_APP_CONFIG"],
      "BUNDLE_PATH" => ENV["BUNDLE_PATH"],
      "HOME" => ENV.fetch("HOME"),
      "PATH" => ENV.fetch("PATH"),
      "TMPDIR" => ENV["TMPDIR"],
      "MIGRATION_BASELINE_TAGS" => baseline_tags
    }.compact

    # [script, script] (argv0 form) — a bare string gets word-split by
    # spawn, which breaks on checkout paths containing spaces.
    Open3.capture3(env, [script, script], chdir: root, unsetenv_others: true)
  end

  it "skips baseline comparisons (but still runs the scratch check) when none of the configured tags exist" do
    stdout, stderr, status = run_check("spec-fake-baseline-one spec-fake-baseline-two")

    expect(status).to be_success, "stdout=#{stdout}\nstderr=#{stderr}"
    expect(stdout).to include("[migration-baselines] checking scratch primary migration path")
    expect(stdout).to include(
      "no baseline tags (spec-fake-baseline-one, spec-fake-baseline-two) found locally or on origin " \
      "— skipping baseline comparisons (nothing deployed from this repository yet)"
    )
    expect(stdout).to include("[migration-baselines] ok")
  end

  it "still fails when some but not all configured baseline tags exist" do
    system("git", "tag", "spec-fake-baseline-real", "HEAD", chdir: root, exception: true)

    begin
      stdout, stderr, status = run_check("spec-fake-baseline-real spec-fake-baseline-missing")

      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("[migration-baselines] missing migration baseline tag(s): spec-fake-baseline-missing")
      expect(stdout).not_to include("[migration-baselines] ok")
    ensure
      system("git", "tag", "-d", "spec-fake-baseline-real", chdir: root, exception: false)
    end
  end
end
