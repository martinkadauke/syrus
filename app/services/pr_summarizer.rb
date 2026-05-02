require "json"
require "tmpdir"

# Single-shot claude call that authors a PR title + body from the issue
# and the agent's diff. Reuses AgentInvocation for the subprocess +
# stream-json parsing, but pinned to max_turns: 1 (no tool exploration —
# just one assistant text response) and rooted in a tmpdir so it has no
# filesystem context to wander into.
class PrSummarizer
  DEFAULT_TIMEOUT_SECONDS = 2.minutes.to_i

  Result = Data.define(:title, :body, :error) do
    def success? = error.nil?
  end

  # Test seam — let specs swap in a fake summarizer runner without
  # exec'ing claude. Same shape as AgentInvocation.agent_runner.
  class << self
    attr_accessor :runner
  end

  def initialize(issue:, diff:, oauth_token:,
                 log_sink: ->(_) { },
                 runner: nil,
                 timeout: DEFAULT_TIMEOUT_SECONDS)
    @issue = issue
    @diff = diff
    @oauth_token = oauth_token
    @log_sink = log_sink
    @runner = runner || self.class.runner
    @timeout = timeout
  end

  def call
    prompt = Prompts::PullRequestSummary.new(issue: @issue, diff: @diff).to_s

    Dir.mktmpdir("syrus-summarize") do |tmpdir|
      result = AgentInvocation.new(
        tmpdir,
        prompt: prompt,
        oauth_token: @oauth_token,
        log_sink: @log_sink,
        runner: @runner,
        timeout: @timeout,
        max_turns: 1
      ).run

      return failure("timed out after #{@timeout}s") if result.timed_out
      return failure("agent reported #{result.outcome || 'error'}") if result.is_error
      return failure("agent exited #{result.exit_status}") unless result.success?
      return failure("empty response") if result.final_text.blank?

      parse(result.final_text)
    end
  rescue StandardError => e
    failure("#{e.class}: #{e.message}")
  end

  private

  def parse(raw)
    text = raw.strip
    # Strip surrounding ```json … ``` fences the agent sometimes adds
    # despite the explicit instruction not to.
    text = text.sub(/\A```(?:json)?\s*\n/, "").sub(/\n```\s*\z/, "").strip

    parsed = JSON.parse(text)
    title = parsed["title"].to_s.strip
    body = parsed["body"].to_s.strip

    return failure("empty title") if title.empty?
    return failure("title too long (#{title.length} chars)") if title.length > 120

    Result.new(title: title, body: body, error: nil)
  rescue JSON::ParserError => e
    failure("invalid JSON: #{e.message[0..120]}")
  end

  def failure(reason)
    Result.new(title: nil, body: nil, error: reason)
  end
end
