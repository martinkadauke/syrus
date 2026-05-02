require "json"
require "open3"

class AgentInvocation
  DEFAULT_TIMEOUT_SECONDS = 30.minutes.to_i
  DEFAULT_MAX_TURNS = 50

  # Outcome of one claude invocation. `turns` is parsed from the final
  # stream-json result event (or nil if claude never reached one).
  Result = Data.define(:turns, :exit_status, :timed_out) do
    def success? = !timed_out && exit_status == 0
  end

  def initialize(workspace_path, prompt:, api_key:,
                 log_sink: ->(_) { },
                 runner: nil,
                 timeout: DEFAULT_TIMEOUT_SECONDS,
                 max_turns: DEFAULT_MAX_TURNS)
    @workspace_path = workspace_path.to_s
    @prompt = prompt
    @api_key = api_key
    @log_sink = log_sink
    @runner = runner || method(:default_runner)
    @timeout = timeout
    @max_turns = max_turns
  end

  def run
    @runner.call(
      workspace_path: @workspace_path,
      prompt: @prompt,
      api_key: @api_key,
      log_sink: @log_sink,
      timeout: @timeout,
      max_turns: @max_turns
    )
  end

  private

  # Spawns `claude --print --output-format stream-json --verbose
  # --max-turns N "<prompt>"` in the worktree with ANTHROPIC_API_KEY set.
  # Streams readable assistant text into log_sink as it arrives, captures
  # num_turns from the final result event, kills the process after timeout.
  def default_runner(workspace_path:, prompt:, api_key:, log_sink:, timeout:, max_turns:)
    env = { "ANTHROPIC_API_KEY" => api_key }
    cmd = [ "claude", "--print",
            "--output-format", "stream-json",
            "--verbose",
            "--max-turns", max_turns.to_s,
            prompt ]

    turns = nil
    timed_out = false

    Open3.popen2e(env, *cmd, chdir: workspace_path) do |stdin, output, wait_thread|
      stdin.close

      killer = Thread.new do
        sleep timeout
        timed_out = true
        kill_tree(wait_thread.pid)
      end

      output.each_line do |line|
        turns = process_event(line, log_sink) || turns
      end

      killer.kill
      status = wait_thread.value
      Result.new(turns: turns, exit_status: status.exitstatus, timed_out: timed_out)
    end
  end

  # Returns num_turns if the line was a result event, nil otherwise.
  # Streams readable text into log_sink for assistant events; falls back
  # to passing non-JSON lines through verbatim.
  def process_event(line, log_sink)
    event = JSON.parse(line.strip)
    case event["type"]
    when "assistant"
      text = event.dig("message", "content")&.find { |c| c["type"] == "text" }&.dig("text")
      log_sink.call(text) if text
      nil
    when "result"
      log_sink.call("[result] turns=#{event['num_turns']}, duration_ms=#{event['duration_ms']}")
      event["num_turns"]
    else
      nil
    end
  rescue JSON::ParserError
    log_sink.call(line.chomp)
    nil
  end

  def kill_tree(pid)
    Process.kill("TERM", pid)
    sleep 5
    Process.kill("KILL", pid) rescue nil
  rescue Errno::ESRCH
    # Already dead; nothing to do.
  end
end
