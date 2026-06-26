# frozen_string_literal: true

require "json"
require "spec_helper"

RSpec.describe "desktop Electron startup" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }
  let(:package_json) { JSON.parse(File.read(File.join(desktop_root, "package.json"))) }
  let(:main_process) { File.read(File.join(desktop_root, "electron/main.ts")) }

  it "uses the same loopback host for Vite and Electron in dev" do
    dev_script = package_json.fetch("scripts").fetch("dev")

    expect(dev_script).to include("vite --host 127.0.0.1")
    expect(dev_script).to include("wait-on http://127.0.0.1:5173")
    expect(main_process).to include('new URL("http://127.0.0.1:5173")')
  end

  it "does not close the ActionCable websocket from its error handler" do
    expect(main_process).to include("const finishSocket = () => {")
    expect(main_process).to include("socket.onerror = () => {\n    finishSocket()\n  }")
    expect(main_process).not_to match(/socket\.onerror = \(\) => \{\s*socket\.close\(\)/m)
  end

  it "loads the preload bridge as CommonJS so Electron exposes syrusDesktop" do
    expect(File).to exist(File.join(desktop_root, "electron/preload.cts"))
    expect(main_process).to include('preload: path.join(__dirname, "preload.cjs")')
  end
end
