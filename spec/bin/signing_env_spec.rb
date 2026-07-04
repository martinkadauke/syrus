# frozen_string_literal: true

require "open3"
require "spec_helper"
require "tmpdir"

# Local desktop signing: bin/signing-env lets bin/release-desktop sign and
# notarize a macOS build (and, in principle, a Windows one) using the same
# env var names release-desktop.yml / sign-windows-test.yml set from repo
# secrets, but read from ~/.config/syrus/ instead — see docs/releasing.md
# and docs/windows-signing.md.
RSpec.describe "bin/signing-env" do
  let(:script_path) { File.expand_path("../../bin/signing-env", __dir__) }
  let(:script) { File.read(script_path, encoding: "UTF-8") }
  let(:release_desktop) { File.read(File.expand_path("../../bin/release-desktop", __dir__), encoding: "UTF-8") }

  it "passes a bash syntax check and is meant to be sourced, not executed" do
    _out, err, status = Open3.capture3("bash", "-n", script_path)
    expect(status.exitstatus).to eq(0), err
    expect(File.executable?(script_path)).to be(false)
  end

  it "is sourced by bin/release-desktop, which loads both loaders before packaging" do
    expect(release_desktop).to include(". \"$ROOT/bin/signing-env\"")
    expect(release_desktop).to match(/syrus_load_mac_signing_env[\s\S]*syrus_load_windows_signing_env[\s\S]*electron-builder/)
  end

  def run_with_home(tmp_home, script_body)
    Open3.capture3({ "HOME" => tmp_home }, "bash", "-c", <<~BASH)
      set -euo pipefail
      source "#{script_path}"
      #{script_body}
    BASH
  end

  it "no-ops when ~/.config/syrus/mac-signing.env is absent" do
    Dir.mktmpdir do |home|
      out, err, status = run_with_home(home, <<~BASH)
        syrus_load_mac_signing_env
        echo "CSC_LINK=[${CSC_LINK:-}]"
      BASH
      expect(status.exitstatus).to eq(0), err
      expect(out).to include("CSC_LINK=[]")
    end
  end

  it "exports mac signing vars and points APPLE_API_KEY at the local .p8 file" do
    Dir.mktmpdir do |home|
      config_dir = File.join(home, ".config", "syrus")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "mac-signing.env"), <<~ENV)
        CSC_LINK=base64cert
        CSC_KEY_PASSWORD=hunter2
        APPLE_API_KEY_ID=KEYID123
        APPLE_API_ISSUER=issuer-uuid
      ENV
      File.write(File.join(config_dir, "apple-api-key.p8"), "-----BEGIN PRIVATE KEY-----\n")
      File.chmod(0o600, File.join(config_dir, "mac-signing.env"))
      File.chmod(0o600, File.join(config_dir, "apple-api-key.p8"))

      out, err, status = run_with_home(home, <<~BASH)
        syrus_load_mac_signing_env
        echo "CSC_LINK=[$CSC_LINK]"
        echo "CSC_KEY_PASSWORD=[$CSC_KEY_PASSWORD]"
        echo "APPLE_API_KEY_ID=[$APPLE_API_KEY_ID]"
        echo "APPLE_API_ISSUER=[$APPLE_API_ISSUER]"
        echo "APPLE_API_KEY=[$APPLE_API_KEY]"
      BASH
      expect(status.exitstatus).to eq(0), err
      expect(err).not_to include("warning:")
      expect(out).to include("CSC_LINK=[base64cert]")
      expect(out).to include("CSC_KEY_PASSWORD=[hunter2]")
      expect(out).to include("APPLE_API_KEY_ID=[KEYID123]")
      expect(out).to include("APPLE_API_ISSUER=[issuer-uuid]")
      expect(out).to include("APPLE_API_KEY=[#{File.join(config_dir, "apple-api-key.p8")}]")
    end
  end

  it "warns when the local credential files are more permissive than 600" do
    Dir.mktmpdir do |home|
      config_dir = File.join(home, ".config", "syrus")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "mac-signing.env"), "CSC_LINK=x\n")
      File.chmod(0o644, File.join(config_dir, "mac-signing.env"))

      _out, err, status = run_with_home(home, "syrus_load_mac_signing_env")
      expect(status.exitstatus).to eq(0), err
      expect(err).to include("mac-signing.env is mode 644, not 600")
    end
  end

  it "guards windows signing env loading to a genuine Windows shell (MINGW/MSYS/CYGWIN)" do
    Dir.mktmpdir do |home|
      config_dir = File.join(home, ".config", "syrus")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "windows-signing.env"), "AZURE_TENANT_ID=should-not-load\n")

      out, err, status = run_with_home(home, <<~BASH)
        syrus_load_windows_signing_env
        echo "AZURE_TENANT_ID=[${AZURE_TENANT_ID:-}]"
      BASH
      expect(status.exitstatus).to eq(0), err
      # This test runs on Darwin/Linux, so uname -s is never MINGW/MSYS/CYGWIN —
      # the loader must stay inert here even though the file exists.
      expect(out).to include("AZURE_TENANT_ID=[]")
    end

    expect(script).to match(/MINGW\*\|MSYS\*\|CYGWIN\*/)
  end

  it "documents the local env file convention in docs/releasing.md and docs/windows-signing.md" do
    releasing = File.read(File.expand_path("../../docs/releasing.md", __dir__), encoding: "UTF-8")
    expect(releasing).to include("~/.config/syrus/mac-signing.env")
    expect(releasing).to include("apple-api-key.p8")

    windows_signing = File.read(File.expand_path("../../docs/windows-signing.md", __dir__), encoding: "UTF-8")
    expect(windows_signing).to include("~/.config/syrus/windows-signing.env")
    expect(windows_signing).to include("Invoke-TrustedSigning")
  end
end
