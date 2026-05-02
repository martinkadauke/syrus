require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  def with_env(**vars)
    saved = vars.transform_values { |_| nil }
    saved.each_key { |k| saved[k] = ENV[k.to_s] }
    vars.each { |k, v| ENV[k.to_s] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
  end

  describe "#app_revision" do
    it "returns 'dev' when GIT_SHA isn't set" do
      with_env(GIT_SHA: nil) do
        expect(helper.app_revision).to eq("dev")
      end
    end

    it "returns the baked GIT_SHA when present" do
      with_env(GIT_SHA: "abc1234") do
        expect(helper.app_revision).to eq("abc1234")
      end
    end

    it "treats blank GIT_SHA as unset" do
      with_env(GIT_SHA: "") do
        expect(helper.app_revision).to eq("dev")
      end
    end
  end

  describe "#app_revision_url" do
    it "is nil for the dev revision" do
      with_env(GIT_SHA: nil) do
        expect(helper.app_revision_url).to be_nil
      end
    end

    it "links to the GitHub commit when GIT_SHA is set" do
      with_env(GIT_SHA: "abc1234") do
        expect(helper.app_revision_url).to eq("https://github.com/tkadauke/syrus/commit/abc1234")
      end
    end
  end

end
