require "rails_helper"
require "tmpdir"

RSpec.describe RepoPrepPlan do
  around do |ex|
    Dir.mktmpdir("syrus-repo-prep") { |dir| @dir = dir; ex.run }
  end

  def write(rel, contents = "")
    path = File.join(@dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  describe ".syrus.yml" do
    it "uses prepare: list verbatim" do
      write(".syrus.yml", <<~YAML)
        prepare:
          - bundle install --jobs 4
          - npm ci
      YAML
      result = described_class.for(@dir)
      expect(result.commands).to eq([ "bundle install --jobs 4", "npm ci" ])
      expect(result.source).to eq(".syrus.yml")
    end

    it "treats prepare: [] as explicit no-op" do
      write(".syrus.yml", "prepare: []\n")
      result = described_class.for(@dir)
      expect(result.commands).to be_empty
      expect(result.note).to match(/no commands/)
    end

    it "treats prepare: false as opt-out" do
      write(".syrus.yml", "prepare: false\n")
      result = described_class.for(@dir)
      expect(result.commands).to be_empty
      expect(result.note).to match(/opted out/)
    end

    it "treats unexpected prepare: types as no-op (with diagnostic)" do
      write(".syrus.yml", "prepare: bundle install\n")  # string, not array
      result = described_class.for(@dir)
      expect(result.commands).to be_empty
      expect(result.note).to match(/must be an array/)
    end

    it "doesn't fall back to auto-detect when .syrus.yml exists but has no prepare key" do
      write(".syrus.yml", "other_setting: 42\n")
      write("Gemfile", "")
      result = described_class.for(@dir)
      expect(result.commands).to be_empty
      expect(result.source).to eq(".syrus.yml")
    end

    it "captures parse errors without raising" do
      write(".syrus.yml", "prepare:\n  - bundle install\n  -\nbroken: [\n")
      result = described_class.for(@dir)
      expect(result.commands).to be_empty
      expect(result.note).to match(/YAML parse error/)
    end
  end

  describe "auto-detect" do
    it "Gemfile → bundle install" do
      write("Gemfile", "")
      expect(described_class.for(@dir).commands).to eq([ "bundle install" ])
    end

    it "yarn.lock wins over package.json + package-lock.json" do
      write("package.json", "{}")
      write("package-lock.json", "{}")
      write("yarn.lock", "")
      expect(described_class.for(@dir).commands).to eq([ "yarn install --frozen-lockfile" ])
    end

    it "pnpm-lock.yaml wins over package-lock.json" do
      write("package-lock.json", "{}")
      write("pnpm-lock.yaml", "")
      expect(described_class.for(@dir).commands).to eq([ "pnpm install --frozen-lockfile" ])
    end

    it "package-lock.json → npm ci" do
      write("package.json", "{}")
      write("package-lock.json", "{}")
      expect(described_class.for(@dir).commands).to eq([ "npm ci" ])
    end

    it "bare package.json → npm install" do
      write("package.json", "{}")
      expect(described_class.for(@dir).commands).to eq([ "npm install" ])
    end

    it "Gemfile + Node lockfile → only Gemfile (first match wins; no double-install)" do
      write("Gemfile", "")
      write("yarn.lock", "")
      result = described_class.for(@dir)
      expect(result.commands).to eq([ "bundle install" ])
      expect(result.source).to include("Gemfile")
    end

    it "no recognized signals → empty + diagnostic" do
      result = described_class.for(@dir)
      expect(result.commands).to be_empty
      expect(result.note).to match(/no recognized signals/)
    end
  end
end
