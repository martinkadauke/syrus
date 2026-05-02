require "rails_helper"

RSpec.describe GitRunner do
  it "returns merged stdout/stderr on success" do
    output = described_class.new.run("--version")
    expect(output).to match(/git version/)
  end

  it "raises GitError with the failed command on non-zero exit" do
    expect {
      described_class.new.run("definitely-not-a-real-subcommand")
    }.to raise_error(GitRunner::GitError) do |err|
      expect(err.exit_status).not_to eq(0)
      expect(err.command).to include("definitely-not-a-real-subcommand")
    end
  end

  it "streams each output line to the log_sink as it arrives" do
    lines = []
    described_class.new(log_sink: ->(l) { lines << l }).run("--version")
    expect(lines.length).to be >= 1
    expect(lines.join).to match(/git version/)
  end

  it "honors chdir" do
    Dir.mktmpdir do |dir|
      described_class.new.run("init", chdir: dir)
      expect(File.directory?(File.join(dir, ".git"))).to be true
    end
  end
end
