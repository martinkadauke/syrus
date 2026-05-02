require "json"
require "open3"

class AgentInvocation
  DEFAULT_TIMEOUT_SECONDS = 30.minutes.to_i
  DEFAULT_MAX_TURNS = 50

  # Outcome of one claude invocation. `turns` is parsed from the final
  # stream-json result event; `outcome` is the result event's subtype
  # ("success" / "error_max_turns" / "error_during_execution") and
  # `is_error` mirrors its is_error boolean.
  Result = Data.define(:turns, :exit_status, :timed_out, :is_error, :outcome) do
    def success? = !timed_out && exit_status == 0 && !is_error
  end

  def initialize(workspace_path, prompt:, oauth_token:,
                 log_sink: ->(_) { },
                 runner: nil,
                 timeout: DEFAULT_TIMEOUT_SECONDS,
                 max_turns: DEFAULT_MAX_TURNS)
    @workspace_path = workspace_path.to_s
    @prompt = prompt
    @oauth_token = oauth_token
    @log_sink = log_sink
    @runner = runner || method(:default_runner)
    @timeout = timeout
    @max_turns = max_turns
  end

  def run
    @runner.call(
      workspace_path: @workspace_path,
      prompt: @prompt,
      oauth_token: @oauth_token,
      log_sink: @log_sink,
      timeout: @timeout,
      max_turns: @max_turns
    )
  end

  private

  # Spawns `claude --print --output-format stream-json --verbose
  # --dangerously-skip-permissions --max-turns N "<prompt>"` in the
  # worktree with CLAUDE_CODE_OAUTH_TOKEN set. Streams readable assistant
  # text into log_sink, captures num_turns + is_error + subtype from the
  # final result event, kills the process after timeout.
  #
  # --dangerously-skip-permissions is intentional: the agent runs in an
  # isolated per-job worktree, never against the operator's checkout. Same
  # trust posture as letting a human dev pair on a branch.
  def default_runner(workspace_path:, prompt:, oauth_token:, log_sink:, timeout:, max_turns:)
    env = { "CLAUDE_CODE_OAUTH_TOKEN" => oauth_token }
    cmd = [ "claude", "--print",
            "--output-format", "stream-json",
            "--verbose",
            "--dangerously-skip-permissions",
            "--max-turns", max_turns.to_s,
            prompt ]

    metadata = { turns: nil, is_error: false, outcome: nil }
    timed_out = false

    Open3.popen2e(env, *cmd, chdir: workspace_path) do |stdin, output, wait_thread|
      stdin.close

      killer = Thread.new do
        sleep timeout
        timed_out = true
        kill_tree(wait_thread.pid)
      end

      output.each_line do |line|
        update = process_event(line, log_sink)
        metadata.merge!(update.compact) if update
      end

      killer.kill
      status = wait_thread.value
      Result.new(
        turns: metadata[:turns],
        exit_status: status.exitstatus,
        timed_out: timed_out,
        is_error: metadata[:is_error],
        outcome: metadata[:outcome]
      )
    end
  end

  # Returns a hash of metadata updates if the line was a result event.
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
      log_sink.call("[result] subtype=#{event['subtype']}, is_error=#{event['is_error']}, turns=#{event['num_turns']}, duration_ms=#{event['duration_ms']}")
      {
        turns: event["num_turns"],
        is_error: event["is_error"],
        outcome: event["subtype"]
      }
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
