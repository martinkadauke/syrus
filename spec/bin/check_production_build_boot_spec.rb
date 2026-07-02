# frozen_string_literal: true

require "open3"
require "rails_helper"

RSpec.describe "bin/check-production-build-boot" do
  let(:root) { Rails.root.to_s }
  let(:script) { File.join(root, "bin/check-production-build-boot") }

  it "boots production build mode without connecting to the database" do
    stdout, stderr, status = Open3.capture3(
      {
        "BUNDLE_APP_CONFIG" => ENV["BUNDLE_APP_CONFIG"],
        "BUNDLE_PATH" => ENV["BUNDLE_PATH"],
        "HOME" => ENV.fetch("HOME"),
        "PATH" => ENV.fetch("PATH"),
        "TMPDIR" => ENV["TMPDIR"]
      }.compact,
      # [script, script] (argv0 form) — a bare string gets word-split by
      # spawn, which breaks on checkout paths containing spaces.
      [script, script],
      chdir: root,
      unsetenv_others: true
    )

    expect(status).to be_success, "stdout=#{stdout.inspect}\nstderr=#{stderr.inspect}"
    expect(stdout).to include("[check-production-build-boot] rails booted")
    expect(stdout).to include("[check-production-build-boot] ok")
    expect(stderr).to be_empty
  end
end
