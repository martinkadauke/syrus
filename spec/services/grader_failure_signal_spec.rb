require "rails_helper"

RSpec.describe GraderFailureSignal do
  describe ".timeout_like_entry?" do
    it "recognizes process timeout metadata" do
      entry = { "status" => "failed", "timed_out" => true, "exit_code" => 124 }

      expect(described_class.timeout_like_entry?(entry)).to be(true)
    end

    it "recognizes test-runner timeout output" do
      entry = { "status" => "failed", "timed_out" => false, "exit_code" => 1, "output" => "Error: Test timed out in 5000ms." }

      expect(described_class.timeout_like_entry?(entry)).to be(true)
    end

    it "does not treat explicit non-timeout exit 124 as a timeout by itself" do
      entry = { "status" => "failed", "timed_out" => false, "exit_code" => 124, "output" => "assertion failed" }

      expect(described_class.timeout_like_entry?(entry)).to be(false)
    end
  end

  describe ".timeout_only_latest_failure?" do
    it "only considers failed required entries in the latest failing iteration" do
      iterations = [
        [
          { "name" => "rspec", "status" => "failed", "required" => true, "output" => "assertion failed" }
        ],
        [
          { "name" => "react-tests", "status" => "failed", "required" => true, "output" => "Error: Test timed out in 5000ms." },
          { "name" => "optional-lint", "status" => "failed", "required" => false, "output" => "assertion failed" }
        ]
      ]

      expect(described_class.timeout_only_latest_failure?(iterations)).to be(true)
    end
  end
end
