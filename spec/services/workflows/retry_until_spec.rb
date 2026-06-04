require "rails_helper"

RSpec.describe Workflows::RetryUntil do
  describe "#initialize" do
    it "stores the max iterations and stringifies repair and check step names" do
      retry_until = described_class.new(
        max_iterations: 5,
        repair: [ :implement ],
        check: [ :grader_fanout, :grader_collect ]
      )

      expect(retry_until.max_iterations).to eq(5)
      expect(retry_until.repair_steps).to eq(%w[ implement ])
      expect(retry_until.check_steps).to eq(%w[ grader_fanout grader_collect ])
    end

    it "rejects empty repair steps" do
      expect { described_class.new(repair: [], check: [ :grade ]) }
        .to raise_error(ArgumentError, "retry_until repair steps required")
    end

    it "rejects empty check steps" do
      expect { described_class.new(repair: [ :implement ], check: []) }
        .to raise_error(ArgumentError, "retry_until check steps required")
    end
  end

  describe "#step_kinds" do
    it "returns repair and check steps when repair_first is true" do
      retry_until = described_class.new(
        repair: [ :implement ],
        check: [ :grader_fanout, :grader_collect ],
        repair_first: true
      )

      expect(retry_until.step_kinds).to eq(%w[ implement grader_fanout grader_collect ])
    end

    it "returns only check steps when repair_first is false" do
      retry_until = described_class.new(
        repair: [ :landing_fix ],
        check: [ :grader_fanout, :grader_collect ],
        repair_first: false
      )

      expect(retry_until.step_kinds).to eq(%w[ grader_fanout grader_collect ])
      expect(retry_until.iteration_step_kinds).to eq(%w[ landing_fix grader_fanout grader_collect ])
    end
  end

  describe "#retry_until?" do
    it "returns true" do
      retry_until = described_class.new(repair: [ :implement ], check: [ :grade ])

      expect(retry_until.retry_until?).to be(true)
    end
  end

  describe "#to_chain_template" do
    it "serializes the retry_until template" do
      retry_until = described_class.new(
        max_iterations: 2,
        repair_first: false,
        repair: [ :landing_fix ],
        check: [ :grader_fanout, :grader_collect ]
      )

      expect(retry_until.to_chain_template).to eq(
        "type" => "retry_until",
        "max_iterations" => 2,
        "repair" => %w[ landing_fix ],
        "check" => %w[ grader_fanout grader_collect ],
        "repair_first" => false
      )
    end
  end
end
