# frozen_string_literal: true

require "spec_helper"

RSpec.describe "website home page" do
  def read_website(path)
    File.read(File.expand_path("../../website/#{path}", __dir__))
  end

  let(:page) { read_website("app/page.tsx") }
  let(:site_copy) { read_website("lib/site.ts") }
  let(:nav) { read_website("components/nav.tsx") }
  let(:normalized_copy) { site_copy.gsub(/\s+/, " ") }

  it "assembles the current Next.js landing page from the product sections" do
    expect(page).to include("<Hero")
    expect(page).to include("<TeamWorkflow")
    expect(page).to include("<Features")
    expect(page).to include("<EntryPoints")
    expect(page).to include("<Demo")
  end

  it "explains Syrus as owner-controlled AI work from goal to merged pull request" do
    expect(site_copy).to include("Ship more of your roadmap.")
    expect(normalized_copy).to include("put AI to work from goal to merged pull request")
    expect(normalized_copy).to include("turning conversations into tracked epics and tickets")
    expect(normalized_copy).to include("keeping a human review on every merge")
    expect(normalized_copy).to include("what it cost")
  end

  it "uses real current anchors and pages for primary calls to action" do
    expect(nav).to include('href: "/#how"')
    expect(nav).to include('href: "/#features"')
    expect(nav).to include('href: "/#entry-points"')
    expect(nav).to include('href="/#demo"')
    expect(nav).to include("<DownloadButton")
  end
end
