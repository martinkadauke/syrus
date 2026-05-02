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

  describe ".redact" do
    it "redacts the token in an x-access-token URL" do
      input = "git fetch https://x-access-token:github_pat_11ABC123XYZ@github.com/owner/repo.git"
      expect(described_class.redact(input)).to eq(
        "git fetch https://x-access-token:[REDACTED]@github.com/owner/repo.git"
      )
    end

    it "redacts ghp_-prefixed tokens too (older PATs)" do
      input = "fatal: unable to access 'https://x-access-token:ghp_secret@github.com/o/r.git/'"
      expect(described_class.redact(input)).to include("[REDACTED]")
      expect(described_class.redact(input)).not_to include("ghp_secret")
    end

    it "leaves non-auth URLs and other strings alone" do
      expect(described_class.redact("https://github.com/foo/bar.git")).to eq("https://github.com/foo/bar.git")
      expect(described_class.redact("nothing to see here")).to eq("nothing to see here")
    end
  end

  describe "GitError redaction (defense in depth)" do
    it "scrubs the token from the stored command + the exception message" do
      auth_url = "https://x-access-token:github_pat_AAA111@github.com/o/r.git"
      err = GitRunner::GitError.new([ "fetch", auth_url, "+refs/heads/*:refs/heads/*" ], 128, "")
      expect(err.command).to include(/\[REDACTED\]/)
      expect(err.message).to include("[REDACTED]")
      expect(err.command).not_to include(/github_pat_AAA111/)
      expect(err.message).not_to include("github_pat_AAA111")
    end

    it "scrubs the token from captured stderr/stdout (git prints the URL on network errors)" do
      err = GitRunner::GitError.new(
        [ "fetch" ], 128,
        "fatal: unable to access 'https://x-access-token:ghp_oops@github.com/o/r.git/': Could not resolve host"
      )
      expect(err.output).to include("[REDACTED]")
      expect(err.output).not_to include("ghp_oops")
    end
  end

  describe "streaming redaction" do
    it "redacts tokens that git echoes into stderr/stdout before they reach log_sink" do
      lines = []
      runner = described_class.new(log_sink: ->(l) { lines << l })
      auth_url_with_garbage_path = "https://x-access-token:github_pat_BBB@github.com/this-repo/does-not-exist-12345.git"
      expect {
        runner.run("ls-remote", auth_url_with_garbage_path)
      }.to raise_error(GitRunner::GitError)
      combined = lines.join
      expect(combined).not_to include("github_pat_BBB"), "log_sink received an unredacted token: #{combined.inspect}"
    end
  end
end
