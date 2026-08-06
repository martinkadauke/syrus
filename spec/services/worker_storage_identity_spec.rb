require "rails_helper"
require "tmpdir"

RSpec.describe WorkerStorageIdentity do
  it "persists one durable id inside the data root" do
    Dir.mktmpdir("syrus-worker-storage") do |dir|
      first = described_class.key(data_root: dir)
      second = described_class.key(data_root: dir)

      expect(first).to be_present
      expect(second).to eq(first)
      expect(File.read(File.join(dir, described_class::FILE_NAME))).to include(first)
    end
  end

  it "sanitizes the id for queue names" do
    expect(described_class.sanitize(" worker/key with spaces ")).to eq("worker-key-with-spaces")
  end

  it "builds the resume queue name from the durable id" do
    Dir.mktmpdir("syrus-worker-storage") do |dir|
      File.write(File.join(dir, described_class::FILE_NAME), "storage-a\n")

      expect(described_class.queue_name(data_root: dir)).to eq("resume-storage-a")
    end
  end
end
