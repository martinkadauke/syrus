require "open3"

class GitRunner
  class GitError < StandardError
    attr_reader :command, :exit_status, :output

    def initialize(command, exit_status, output)
      @command = command
      @exit_status = exit_status
      @output = output
      super("git #{command.join(' ')} exited #{exit_status}")
    end
  end

  # log_sink: a callable that receives each output line (stdout+stderr merged).
  # Defaults to a no-op so unit tests don't need to wire one up.
  def initialize(log_sink: ->(_line) { }, env: {})
    @log_sink = log_sink
    @env = env
  end

  # run("clone", "--bare", url, dest, chdir: nil)
  def run(*args, chdir: nil)
    cmd = [ "git", *args.map(&:to_s) ]
    output = +""

    Open3.popen2e(@env, *cmd, chdir: chdir || Dir.pwd) do |stdin, stream, wait_thread|
      stdin.close
      stream.each_line do |line|
        output << line
        @log_sink.call(line)
      end
      status = wait_thread.value
      raise GitError.new(args, status.exitstatus, output) unless status.success?
    end

    output
  end
end
