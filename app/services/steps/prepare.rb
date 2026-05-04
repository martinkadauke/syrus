require "open3"

module Steps
  # First step in Initial / Replay / PrFeedback / CiFailure
  # workflows. Runs deterministic setup work in the workspace
  # BEFORE handing off to the agent — package-manager installs
  # mostly (`bundle install`, `npm ci`, etc.) so the agent doesn't
  # burn turns/tokens watching dependencies download.
  #
  # Source of commands: RepoPrepPlan reads `.syrus.yml` from the
  # repo root, falls back to auto-detect on common lockfile
  # signals. Empty plan = step succeeds with a one-line "nothing
  # to do" message — chain shape stays uniform across workflows
  # whether or not the repo opts in.
  #
  # Per-command timeout caps a hung install so the workflow can
  # fail loudly instead of pegging the worker thread until the
  # reaper trips.
  class Prepare < Base
    PER_COMMAND_TIMEOUT = 10.minutes.to_i

    def call
      workspace.setup
      plan = RepoPrepPlan.for(workspace.path)

      log("[prepare] source: #{plan.source}")
      log("[prepare] note: #{plan.note}") if plan.note

      if plan.commands.empty?
        log("[prepare] no commands to run; skipping")
        return
      end

      plan.commands.each_with_index do |cmd, i|
        log("[prepare] (#{i + 1}/#{plan.commands.size}) $ #{cmd}")
        run_shell(cmd)
      end

      log("[prepare] all commands completed successfully")
    end

    private

    # `bash -c` so quoting / pipelines / && in commands work.
    # cwd = workspace path. Streams stdout+stderr (popen2e merges
    # them) into JobLog one line at a time so the operator can
    # watch the install live. Hard timeout via a watcher thread
    # that SIGTERMs the process tree if it exceeds the budget.
    def run_shell(cmd)
      timed_out = false
      Open3.popen2e("bash", "-c", cmd, chdir: workspace.path.to_s) do |stdin, output, wait_thread|
        stdin.close
        killer = Thread.new do
          sleep PER_COMMAND_TIMEOUT
          timed_out = true
          kill_tree(wait_thread.pid)
        end
        output.each_line { |line| log(line.chomp, kind: "system") }
        killer.kill
        status = wait_thread.value
        if timed_out
          raise StepFailed, "prepare command timed out after #{PER_COMMAND_TIMEOUT}s: #{cmd}"
        elsif !status.success?
          raise StepFailed, "prepare command failed (exit #{status.exitstatus}): #{cmd}"
        end
      end
    end

    def kill_tree(pid)
      Process.kill("TERM", pid)
      sleep 5
      Process.kill("KILL", pid) rescue nil
    rescue Errno::ESRCH
      # Already dead.
    end
  end
end
