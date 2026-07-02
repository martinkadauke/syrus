# frozen_string_literal: true

require "spec_helper"

# The app manages the local Docker stack it installed: ensure-on-launch, a
# transition-only watchdog, and explicit Backend-menu controls. Quitting the
# app must leave the stack running (jobs keep flowing), so nothing here may
# tear containers down or touch volumes.
RSpec.describe "desktop backend lifecycle" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }

  def read(relative_path)
    File.read(File.join(desktop_root, relative_path), encoding: "UTF-8")
  end

  let(:lifecycle) { read("electron/installer/backendLifecycle.ts") }
  let(:main_process) { read("electron/main.ts") }
  let(:backend_status) { read("src/BackendStatus.tsx") }

  it "runs compose from the state dir with the pinned project name and augmented PATH" do
    expect(lifecycle).to include('[...prefixArgs, "-p", "syrus", ...args]')
    expect(lifecycle).to include("cwd: stateDir()")
    expect(lifecycle).to include("env: execEnv()")
  end

  it "stops with `compose stop` and never destroys containers or volumes" do
    expect(lifecycle).to include('compose(["stop"])')
    expect(lifecycle).not_to include('"down"')
  end

  it "never pulls images — updates happen only through the installer" do
    expect(lifecycle).not_to match(/compose\(\[[^\]]*"pull"/)
  end

  it "gates every action on local mode so remote instances are untouched" do
    expect(lifecycle.scan(/getBackendMode\(\) !== "local"/).length).to be >= 3
  end

  it "supervises on launch: ensure running plus a transition-only watchdog" do
    expect(main_process).to include("startLocalBackendSupervision()")
    expect(lifecycle).to include("export const ensureRunning")
    expect(lifecycle).to include("WATCHDOG_INTERVAL_MS = 30_000")
    expect(lifecycle).to include("if (healthy === lastHealthy)")
  end

  it "diagnoses daemon-down vs containers-down without auto-restarting" do
    expect(lifecycle).to include('(await daemonUp()) ? "containers-down" : "daemon-down"')
    expect(lifecycle).not_to match(/onHealthyChanged[\s\S]*startBackend\(\)/)
  end

  it "adds the Backend menu only for local installs, with a confirmed stop" do
    expect(main_process).to include('if (getBackendMode() === "local") {')
    expect(main_process).to include('label: "Backend"')
    expect(main_process).to include("confirmStopBackend")
    expect(main_process).to match(/confirmStopBackend[\s\S]*?showMessageBox/)
    expect(main_process).to include('"Open Install Log"')
  end

  it "suppresses the watchdog after a deliberate stop" do
    # Backend -> Stop Syrus shows the "stopped" page; the next watchdog tick
    # must not overwrite it with a "containers-down" failure.
    stop_fn = lifecycle[/export const stopBackend[\s\S]*?\n\}/]
    expect(stop_fn).to include("lastHealthy = false")
  end

  it "makes restart honest and surfaces refused menu actions" do
    restart_fn = lifecycle[/export const restartBackend[\s\S]*?\n\}/]
    expect(restart_fn).to include("if (!stopped)")
    expect(main_process).to include("runBackendAction")
    expect(main_process).to include("reportBackendActionFailure")
  end

  it "bounds the daemon wait by wall clock with short probes" do
    # Iteration-counted polls with 10s docker-info timeouts stretched the
    # nominal 3-minute wait to ~18 minutes against a wedged daemon.
    expect(lifecycle).to include("DAEMON_WAIT_DEADLINE_MS")
    expect(lifecycle).to include("await daemonUp(2_000)")
    expect(lifecycle).not_to include("DAEMON_WAIT_POLLS")
  end

  it "starts supervision when a local install completes, not only on Open Syrus" do
    on_state = main_process[/onState: \(state\) => \{[\s\S]*?\n    \}/]
    expect(on_state).to include('state.phase === "done" && state.mode === "local"')
    expect(on_state).to include("startLocalBackendSupervision()")
  end

  it "rebuilds the menu and starts supervision when onboarding finishes" do
    finish = main_process[/const finishOnboarding = async \(\) => \{[\s\S]*?\n\}/]
    expect(finish).to include("createMenu()")
    expect(finish).to include("startLocalBackendSupervision()")
  end

  it "explains each unavailable state on the status page" do
    %w[daemon-down containers-down stopped remote].each do |detail|
      expect(backend_status).to include(%("#{detail}")).or include("#{detail}:")
    end
  end
end
