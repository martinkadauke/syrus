# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"
require "socket"

# The multi-node deployment splits queues across two worker configs selected per
# pod via SOLID_QUEUE_CONFIG, while single-host / Compose keeps running the full
# config/queue.yml on one worker. These invariants guard both properties:
#   - Compose safety: queue.yml must still cover EVERY queue on one worker.
#   - Clean split:    home ∪ compute must equal queue.yml's queues, with the
#                     heavy/search queues partitioned (no queue orphaned, none
#                     double-run across the two tiers).
#   - Resume affinity: every worker config must consume this pod's own
#                     resume-<hostname> queue, matching Workflow.resume_queue_name.
RSpec.describe "queue partitioning" do
  ROOT = Rails.root

  # The app's full queue vocabulary. Sources of truth:
  #   :runs / :merges / :default  — Workflows::*.queue_name (workflow templates)
  #   :chat / :videos / :default  — queue_as on ChatTurnJob / video jobs / etc.
  APP_QUEUES = %w[runs merges chat default videos].freeze

  # Where each non-resume queue must run in the multi-node split.
  HOME_QUEUES    = %w[chat default videos].freeze
  COMPUTE_QUEUES = %w[runs merges].freeze

  def load_config(relative)
    raw = File.read(ROOT.join(relative))
    YAML.safe_load(ERB.new(raw).result, aliases: true, permitted_classes: [ Symbol ])
  end

  # All queue tokens (space-separated within each worker's "queues" string)
  # declared in the `default` section, split into resume vs the rest.
  def queues_for(relative)
    workers = Array(load_config(relative).dig("default", "workers"))
    tokens = workers.flat_map { |w| w["queues"].to_s.split }
    resume, regular = tokens.partition { |q| q.start_with?("resume-") }
    { resume: resume, regular: regular }
  end

  it "keeps queue.yml a complete single-worker config (Compose / single-host)" do
    expect(queues_for("config/queue.yml")[:regular].uniq).to match_array(APP_QUEUES)
  end

  it "routes only the search-bound + light queues to the home worker" do
    expect(queues_for("config/queue.home.yml")[:regular].uniq).to match_array(HOME_QUEUES)
  end

  it "routes only the heavy search-free queues to the compute worker" do
    expect(queues_for("config/queue.compute.yml")[:regular].uniq).to match_array(COMPUTE_QUEUES)
  end

  it "partitions every app queue across home and compute with no orphan or overlap" do
    home = queues_for("config/queue.home.yml")[:regular].uniq
    compute = queues_for("config/queue.compute.yml")[:regular].uniq

    expect(home & compute).to be_empty, "a queue is double-run across tiers: #{(home & compute).inspect}"
    expect((home | compute)).to match_array(APP_QUEUES)
  end

  it "gives every worker config this pod's own resume-<hostname> queue" do
    expected = Workflow.resume_queue_name(Socket.gethostname)
    expect(expected).to eq("resume-#{Socket.gethostname}")

    %w[config/queue.yml config/queue.home.yml config/queue.compute.yml].each do |config|
      resume = queues_for(config)[:resume].uniq
      expect(resume).to eq([ expected ]),
        "#{config} must consume exactly its own resume queue, got #{resume.inspect}"
    end
  end
end
