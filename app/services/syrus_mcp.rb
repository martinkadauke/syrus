module SyrusMcp
  # Append a JobLog row from the sidecar process. Same shape as
  # RunJob#log so MCP-driven lines blend into the rest of the
  # transcript and broadcast live via JobLog#broadcasts_to.
  def self.write_log(run, chunk)
    next_seq = (run.job_logs.maximum(:sequence) || -1) + 1
    run.job_logs.create!(chunk: chunk, sequence: next_seq)
  end
end
