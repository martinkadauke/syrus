# frozen_string_literal: true

require "open3"
require "tmpdir"
require "spec_helper"

RSpec.describe "bin/rspec-ci" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:script) { File.join(root, "bin/rspec-ci") }

  def write_stub(path, body)
    File.write(path, body)
    File.chmod(0o755, path)
  end

  it "prepares the base test database before running the parallel suite and ci_only specs" do
    Dir.mktmpdir do |dir|
      bin_dir = File.join(dir, "bin")
      FileUtils.mkdir_p(bin_dir)
      FileUtils.cp(script, File.join(bin_dir, "rspec-ci"))
      log_path = File.join(dir, "calls.log")

      write_stub(File.join(bin_dir, "rails"), <<~BASH)
        #!/usr/bin/env bash
        printf 'rails RAILS_ENV=%s args=%s\\n' "$RAILS_ENV" "$*" >> calls.log
      BASH

      write_stub(File.join(bin_dir, "rspec-fast"), <<~BASH)
        #!/usr/bin/env bash
        printf 'rspec-fast RAILS_ENV=%s COVERAGE=%s args=%s\\n' "$RAILS_ENV" "$COVERAGE" "$*" >> calls.log
      BASH

      write_stub(File.join(bin_dir, "rspec"), <<~BASH)
        #!/usr/bin/env bash
        printf 'rspec RUN_CI_ONLY_SPECS=%s RSPEC_JSON_DIR=%s args=%s\\n' "$RUN_CI_ONLY_SPECS" "$RSPEC_JSON_DIR" "$*" >> calls.log
      BASH

      stdout, stderr, status = Open3.capture3(
        { "PATH" => ENV.fetch("PATH"), "HOME" => ENV.fetch("HOME") },
        "bash",
        File.join(bin_dir, "rspec-ci"),
        "spec/models/job_spec.rb",
        chdir: dir,
        unsetenv_others: true
      )

      expect(status).to be_success, "expected success, got stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      expect(File.read(log_path).lines.map(&:chomp)).to eq([
        "rails RAILS_ENV=test args=db:test:prepare",
        "rspec-fast RAILS_ENV=test COVERAGE=false args=spec/models/job_spec.rb",
        "rspec RUN_CI_ONLY_SPECS=true RSPEC_JSON_DIR=.syrus/rspec-json args=--tag ci_only --format progress --format json --out .syrus/rspec-json/rspec-ci-only.json spec/models/job_spec.rb"
      ])
    end
  end
end
