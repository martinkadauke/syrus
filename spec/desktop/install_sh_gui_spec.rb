# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "spec_helper"

# install.sh is the single source of truth for the Docker install workflow.
# The desktop app drives it headlessly (--json --non-interactive
# --skip-runtime-install --target-dir …), so this spec pins the machine
# interface: flag surface, NDJSON progress protocol, exit-code classes, and
# the encryption-key guard. Dynamic examples run the real script against a
# stubbed `docker` binary — no daemon, no side effects, fast.
RSpec.describe "install.sh GUI interface" do
  let(:repo_root) { File.expand_path("../..", __dir__) }
  let(:script) { File.join(repo_root, "install.sh") }
  let(:script_text) { File.read(script, encoding: "UTF-8") }

  def run_install(*args, stub_dir: nil)
    path = [stub_dir, "/usr/bin", "/bin"].compact.join(":")
    Open3.capture3({ "PATH" => path }, "bash", script, *args)
  end

  # A fake `docker` that answers the exact calls the docker path makes.
  # volume_exists controls the encryption-key guard; `compose pull` always
  # fails so the script halts before anything that would need a real daemon.
  def write_docker_stub(dir, volume_exists:)
    stub = File.join(dir, "docker")
    File.write(stub, <<~SH)
      #!/bin/bash
      case "$1" in
        info) exit 0 ;;
        volume) exit #{volume_exists ? 0 : 1} ;;
        compose)
          case "$2" in
            version) exit 0 ;;
            pull) echo "stub: pull refused"; exit 1 ;;
            *) exit 0 ;;
          esac ;;
      esac
      exit 0
    SH
    File.chmod(0o755, stub)
  end

  def parse_events(stdout)
    stdout.lines.map { |line| JSON.parse(line) }
  end

  it "passes a bash syntax check" do
    _out, err, status = Open3.capture3("bash", "-n", script)
    expect(status.exitstatus).to eq(0), err
  end

  it "documents the GUI flag surface and exit codes in --help" do
    out, _err, status = run_install("--help")
    expect(status.exitstatus).to eq(0)
    %w[--non-interactive --json --target-dir --skip-runtime-install --image --port].each do |flag|
      expect(out).to include(flag)
    end
    expect(out).to include("Exit codes:")
  end

  it "keeps the compose project pinned so the syrus_ volume prefix survives any invocation dir" do
    expect(script_text).to include("export COMPOSE_PROJECT_NAME=syrus")
    expect(script_text).to include("docker volume inspect syrus_syrus-data")
  end

  it "classifies every failure with a distinct exit code" do
    expect(script_text).to include('die "No container runtime found. Install OrbStack')
    [10, 11, 12, 20, 30, 40, 41].each do |code|
      expect(script_text).to match(/ #{code}$/), "expected a die call with exit code #{code}"
    end
  end

  it "never installs Homebrew or OrbStack when --skip-runtime-install is set" do
    fn = script_text[/^ensure_docker_runtime\(\) \{.*?\n\}/m]
    expect(fn).to include('"$SKIP_RUNTIME_INSTALL" = "1"')
    expect(fn.index('"$SKIP_RUNTIME_INSTALL" = "1"')).to be < fn.index("ensure_homebrew")
  end

  it "hardens PATH for GUI-spawned processes that lack a login-shell PATH" do
    expect(script_text).to include('$HOME/.orbstack/bin')
    expect(script_text).to include("/Applications/Docker.app/Contents/Resources/bin")
  end

  it "gates success on the Rails health endpoint, not just compose returning" do
    expect(script_text).to include("/up")
    expect(script_text).to match(/emit_step health start/)
  end

  it "rejects GUI flags on the bare-metal path" do
    _out, err, status = run_install("--bare-metal", "--json")
    expect(status.exitstatus).to eq(2)
    expect(err).to include("only apply to --docker")
  end

  it "fails non-interactive runs without a mode as a usage error with a JSON event" do
    out, _err, status = run_install("--json", "--non-interactive")
    expect(status.exitstatus).to eq(2)
    events = parse_events(out)
    expect(events.length).to eq(1)
    expect(events.first).to include("event" => "error", "code" => 2)
  end

  it "rejects a non-numeric --port as a usage error" do
    out, _err, status = run_install("--json", "--docker", "--port", "not-a-port")
    expect(status.exitstatus).to eq(2)
    expect(parse_events(out).last).to include("event" => "error", "code" => 2)
  end

  it "refuses to mint fresh encryption keys when the data volume exists but .env is missing" do
    Dir.mktmpdir do |stub_dir|
      Dir.mktmpdir do |target|
        write_docker_stub(stub_dir, volume_exists: true)
        out, err, status = run_install(
          "--docker", "--json", "--non-interactive", "--skip-runtime-install",
          "--target-dir", target, stub_dir: stub_dir
        )
        expect(status.exitstatus).to eq(20)
        events = parse_events(out)
        expect(events.first).to include("event" => "start", "mode" => "docker")
        step_ids = events.select { |e| e["event"] == "step" }.map { |e| e["id"] }
        expect(step_ids).to include("runtime_check", "compose_resolve", "env_check")
        expect(events.last).to include("event" => "error", "code" => 20, "step" => "env_check")
        expect(err).to include("undecryptable")
        expect(File.exist?(File.join(target, ".env"))).to be(false)
      end
    end
  end

  it "generates .env with substituted secrets, pinned image, and chosen port, idempotently" do
    Dir.mktmpdir do |stub_dir|
      Dir.mktmpdir do |target|
        write_docker_stub(stub_dir, volume_exists: false)
        args = [
          "--docker", "--json", "--non-interactive", "--skip-runtime-install",
          "--target-dir", target, "--port", "4321",
          "--image", "ghcr.io/example/pinned:9.9.9"
        ]
        out, _err, status = run_install(*args, stub_dir: stub_dir)

        # The stub fails `compose pull`, halting the script right after the
        # .env work we want to assert on — classified as exit 30.
        expect(status.exitstatus).to eq(30)
        events = parse_events(out)
        expect(events).to include(
          hash_including("event" => "step", "id" => "env_generate", "status" => "ok")
        )
        expect(events).to include(
          hash_including("event" => "log", "stream" => "pull", "line" => "stub: pull refused")
        )
        expect(events.last).to include("event" => "error", "code" => 30, "step" => "image_pull")

        env = File.read(File.join(target, ".env"), encoding: "UTF-8")
        expect(env).to include("SYRUS_PORT=4321")
        expect(env).to include("SYRUS_APP_HOST=localhost:4321")
        expect(env).to include("SYRUS_IMAGE=ghcr.io/example/pinned:9.9.9")
        expect(env).not_to match(/=generate-me$/)
        expect(File.exist?(File.join(target, "docker-compose.yml"))).to be(true)

        # Re-running must adopt the existing .env, never regenerate secrets.
        rerun_out, _err2, = run_install(*args, stub_dir: stub_dir)
        expect(parse_events(rerun_out)).to include(
          hash_including("event" => "step", "id" => "env_generate", "status" => "skipped")
        )
        expect(File.read(File.join(target, ".env"), encoding: "UTF-8")).to eq(env)
      end
    end
  end
end
