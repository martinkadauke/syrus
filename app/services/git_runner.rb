require "open3"

class GitRunner
  # Redacts tokens out of any string that contains a
  # `https://x-access-token:TOKEN@github.com/...` URL — the form
  # JobWorkspace + RunJob pass when they need authenticated git.
  # Applied to:
  #   - argv stored on GitError (so the exception message is clean
  #     when it bubbles into JobLog / Solid Queue's failed_executions)
  #   - every line streamed to log_sink + captured into `output`
  #     (git prints the full URL in some network-error messages,
  #     e.g. "fatal: unable to access 'https://x-access-token:T@…'")
  AUTH_URL_PATTERN = %r{(https://x-access-token:)[^@\s]+(@)}.freeze

  def self.redact(text)
    text.to_s.gsub(AUTH_URL_PATTERN, '\1[REDACTED]\2')
  end

  class GitError < StandardError
    attr_reader :command, :exit_status, :output

    OUTPUT_TAIL_LIMIT = 1500   # chars; enough to surface git's "fatal: ..." line(s)

    def initialize(command, exit_status, output)
      @command = command.map { |a| GitRunner.redact(a) }
      @exit_status = exit_status
      @output = GitRunner.redact(output)
      super(build_message)
    end

    private

    # Surface the last chunk of git's stdout+stderr in the message so
    # `e.message` (what RunJob's rescue logs) actually tells you what
    # went wrong, instead of "git diff main...HEAD exited 128" with no
    # context. Tail rather than head — git's "fatal: ..." line is
    # typically the last thing emitted.
    def build_message
      base = "git #{@command.join(' ')} exited #{@exit_status}"
      tail = @output.to_s.strip
      return base if tail.empty?
      tail = "...#{tail.last(OUTPUT_TAIL_LIMIT)}" if tail.length > OUTPUT_TAIL_LIMIT
      "#{base}\n#{tail}"
    end
  end

  # log_sink: a callable that receives each output line (stdout+stderr merged).
  # Defaults to a no-op so unit tests don't need to wire one up.
  def initialize(log_sink: ->(_line) { }, env: {})
    @log_sink = log_sink
    @env = env
  end

  # run("clone", "--bare", url, dest, chdir: nil)
  # Per-call env is merged with the instance env (per-call wins).
  # Useful for one-shot flags like GIT_TERMINAL_PROMPT=0 that you
  # only want on git operations that talk to a remote.
  def run(*args, chdir: nil, env: {})
    cmd = [ "git", *args.map(&:to_s) ]
    output = +""

    Open3.popen2e(@env.merge(env), *cmd, chdir: chdir || Dir.pwd) do |stdin, stream, wait_thread|
      stdin.close
      stream.each_line do |raw_line|
        line = self.class.redact(raw_line)
        output << line
        @log_sink.call(line)
      end
      status = wait_thread.value
      raise GitError.new(args, status.exitstatus, output) unless status.success?
    end

    output
  end
end
