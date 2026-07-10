# frozen_string_literal: true

require "spec_helper"

RSpec.describe "website product positioning pages" do
  def read_website(path)
    File.read(File.expand_path("../../website/#{path}", __dir__))
  end

  let(:site_copy) { read_website("lib/site.ts") }
  let(:demo) { read_website("components/demo.tsx") }
  let(:download_page) { read_website("app/download/page.tsx") }
  let(:normalized_copy) { site_copy.gsub(/\s+/, " ") }

  it "links the explanatory sections from the home navigation" do
    nav = read_website("components/nav.tsx")

    expect(nav).to include("How it works")
    expect(nav).to include("/#how")
    expect(nav).to include("Why Syrus")
    expect(nav).to include("/#features")
  end

  it "explains what Syrus is using current product terminology" do
    expect(normalized_copy).to include("epics and tickets")
    expect(normalized_copy).to include("Jobs")
    expect(normalized_copy).to include("tracked job")
    expect(normalized_copy).to include("pull request")
    expect(normalized_copy).to include("landing queue")
    expect(normalized_copy).to include("full transcript, diff, and review")
  end

  it "helps visitors decide whether Syrus fits their workflow" do
    expect(normalized_copy).to include("Self-hosted on your infrastructure")
    expect(normalized_copy).to include("GitHub")
    expect(normalized_copy).to include("Claude or Codex")
    expect(demo).to include("Request a demo")
    expect(download_page).to include("Download Syrus")
  end
end
