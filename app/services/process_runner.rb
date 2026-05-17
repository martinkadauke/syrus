require "open3"

# Small shared wrapper for subprocess lifetime management. Callers still own
# command construction and output parsing; this class owns the boring parts:
# scrubbed env, process-group spawning, timeout/stop handling, streaming, and
# a common result shape.
class ProcessRunner
  Result = Data.define(:exit_status, :timed_out, :stopped, :silent_timed_out, :duration_s) do
    def success? = !timed_out && !stopped && !silent_timed_out && exit_status == 0
    def timed_out? = timed_out
    def stopped? = stopped
    def silent_timed_out? = silent_timed_out
  end

  TERM_GRACE_SECONDS = 5
  READ_CHUNK_BYTES = 16 * 1024

  def self.forwarded_env(keys, extra: {})
    ENV.slice(*keys).merge(extra.compact)
  end

  # `silent_timeout` (seconds, or nil to disable): kill the subprocess
  # if it produces no output for this long. The wall-clock `timeout`
  # is a separate ceiling — the silent timeout fires faster for the
  # common "agent process wedged" failure mode (today's incident: a
  # codex CLI stopped emitting output and the worker thread blocked
  # on the IO.select read forever, holding its SolidQueue claim +
  # concurrency semaphore for the rest of the worker's life).
  #
  # Don't set silent_timeout for inherently bursty commands like
  # `bundle install` or `git clone` — those have natural silent
  # phases longer than any sensible threshold. Reserve for streaming
  # agent invocations where continuous output is the norm.
  def initialize(env:, command:, chdir:, timeout:, stdin_data: nil,
                 unsetenv_others: true, pgroup: true,
                 stop_requested: -> { false },
                 on_output_chunk: nil,
                 on_output_line: nil,
                 kill_grace_seconds: TERM_GRACE_SECONDS,
                 silent_timeout: nil)
    @env = env
    @command = command
    @chdir = chdir.to_s
    @timeout = timeout
    @stdin_data = stdin_data
    @unsetenv_others = unsetenv_others
    @pgroup = pgroup
    @stop_requested = stop_requested
    @on_output_chunk = on_output_chunk
    @on_output_line = on_output_line
    @kill_grace_seconds = kill_grace_seconds
    @silent_timeout = silent_timeout
  end

  def run
    timed_out = false
    stopped = false
    silent_timed_out = false
    result = nil
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Open3.popen2e(@env, *@command,
                  chdir: @chdir,
                  unsetenv_others: @unsetenv_others,
                  pgroup: @pgroup) do |stdin, output, wait_thread|
      write_stdin(stdin)

      killer = Thread.new do
        sleep @timeout
        timed_out = true
        terminate(wait_thread.pid)
      end

      silent_check = ->(last_chunk_at) {
        return false unless @silent_timeout
        return false unless last_chunk_at
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - last_chunk_at
        elapsed >= @silent_timeout
      }

      stream_output(output, wait_thread, silent_check) do
        next if timed_out

        if @stop_requested.call
          stopped = true
          terminate(wait_thread.pid)
          next
        end

        if @last_silent_kill
          silent_timed_out = true
          @last_silent_kill = nil
          terminate(wait_thread.pid)
        end
      end

      killer.kill
      status = wait_thread.value
      result = Result.new(
        exit_status: (timed_out || silent_timed_out) ? nil : (status.exitstatus || 1),
        timed_out: timed_out,
        stopped: stopped,
        silent_timed_out: silent_timed_out,
        duration_s: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      )
    end
    result
  end

  private

  def write_stdin(stdin)
    stdin.write(@stdin_data) if @stdin_data
  ensure
    stdin.close unless stdin.closed?
  end

  def stream_output(output, wait_thread, silent_check)
    line_buffer = +""
    last_chunk_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    loop do
      # The yield block is given a chance to terminate the process
      # based on the stop_requested / silent_timeout signals. The
      # `@last_silent_kill` flag we set just below tells the block
      # to mark the result as silent_timed_out before killing.
      @last_silent_kill = silent_check.call(last_chunk_at)
      yield
      break if wait_thread.respond_to?(:join) && wait_thread.join(0)

      ready, = IO.select([ output ], nil, nil, 0.1)
      next unless ready

      begin
        chunk = output.read_nonblock(READ_CHUNK_BYTES)
        last_chunk_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @on_output_chunk&.call(chunk)
        stream_lines(chunk, line_buffer)
      rescue IO::WaitReadable
        next
      rescue EOFError
        break
      end
    end

    drain_output(output, line_buffer)
    @on_output_line&.call(line_buffer) if @on_output_line && !line_buffer.empty?
  end

  def drain_output(output, line_buffer)
    loop do
      chunk = output.read_nonblock(READ_CHUNK_BYTES)
      @on_output_chunk&.call(chunk)
      stream_lines(chunk, line_buffer)
    rescue IO::WaitReadable
      ready, = IO.select([ output ], nil, nil, 0)
      next if ready
      break
    rescue EOFError
      break
    end
  end

  def stream_lines(chunk, line_buffer)
    return unless @on_output_line

    line_buffer << chunk
    while (newline = line_buffer.index("\n"))
      @on_output_line.call(line_buffer.slice!(0..newline))
    end
  end

  def terminate(pid)
    Process.kill("TERM", -pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @kill_grace_seconds
    loop do
      Process.kill(0, -pid)
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.1
    end
    Process.kill("KILL", -pid)
  rescue Errno::ESRCH
    # Already dead.
  end
end
