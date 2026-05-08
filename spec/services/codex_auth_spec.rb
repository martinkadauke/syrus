require "rails_helper"
require "tmpdir"

RSpec.describe CodexAuth do
  let(:user) { Factories.user(codex_api_key: "sk-test", codex_access_token: "access-token") }

  describe "#prepare!" do
    it "returns the API key and does not run login in api_key mode" do
      called = false
      auth = described_class.new(
        user: user,
        codex_home: "/tmp/codex-home",
        runner: ->(**) { called = true }
      )

      result = auth.prepare!

      expect(result.api_key).to eq("sk-test")
      expect(called).to be(false)
    end

    it "requires an API key in api_key mode" do
      user.update!(codex_api_key: nil)

      expect {
        described_class.new(user: user, codex_home: "/tmp/codex-home").prepare!
      }.to raise_error(CodexAuth::Error, /API key/)
    end

    it "logs CODEX_HOME in with the access token in chatgpt_login mode" do
      user.update!(codex_auth_mode: "chatgpt_login")
      received = nil
      Dir.mktmpdir do |home|
        auth = described_class.new(
          user: user,
          codex_home: home,
          runner: ->(**kwargs) { received = kwargs }
        )

        result = auth.prepare!

        expect(result.api_key).to be_nil
        expect(received).to eq(codex_home: home, access_token: "access-token")
        expect(File.directory?(home)).to be(true)
      end
    end

    it "requires an access token in chatgpt_login mode" do
      user.update!(codex_auth_mode: "chatgpt_login", codex_access_token: nil)

      expect {
        described_class.new(user: user, codex_home: "/tmp/codex-home").prepare!
      }.to raise_error(CodexAuth::Error, /access token/)
    end
  end

  describe "default runner" do
    it "runs codex login with the token on stdin, not argv or env" do
      user.update!(codex_auth_mode: "chatgpt_login")
      captured = nil
      allow(Open3).to receive(:capture2e) do |env, *cmd, **opts|
        captured = { env: env, cmd: cmd, opts: opts }
        [ "ok", instance_double(Process::Status, success?: true) ]
      end

      described_class.new(user: user, codex_home: "/tmp/codex-home").prepare!

      expect(captured[:cmd]).to eq(%w[codex login --with-access-token])
      expect(captured[:opts]).to include(stdin_data: "access-token\n", unsetenv_others: true)
      expect(captured[:env]).to include("CODEX_HOME" => "/tmp/codex-home")
      expect(captured[:env].values).not_to include("access-token")
      expect(captured[:cmd]).not_to include("access-token")
    end

    it "redacts the access token from login failure messages" do
      user.update!(codex_auth_mode: "chatgpt_login")
      allow(Open3).to receive(:capture2e)
        .and_return([ "bad access-token", instance_double(Process::Status, success?: false) ])

      expect {
        described_class.new(user: user, codex_home: "/tmp/codex-home").prepare!
      }.to raise_error(CodexAuth::Error, /bad \[redacted\]/)
    end
  end
end
