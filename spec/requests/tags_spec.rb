require "rails_helper"

RSpec.describe "Tags", type: :request do
  let(:user) { Factories.user }
  let(:other) { Factories.user }

  before { sign_in_as(user) }

  it "serves the React tags shell" do
    get tags_path

    expect(response).to be_successful
    expect(response.body).to include('id="syrus-spa-root"')
  end

  it "lists only the current user's tags in the legacy fallback" do
    Factories.tag(user: user, name: "mine", color: "blue")
    Factories.tag(user: other, name: "theirs", color: "red")

    get legacy_tags_path

    expect(response.body).to include("mine")
    expect(response.body).not_to include("theirs")
  end

  it "renders the per-user settings nav with Tags as the active tab" do
    get legacy_tags_path

    document = Nokogiri::HTML(response.body)
    nav_links = document.css("nav a").map { |a| [ a.text.strip, a["href"] ] }
    expect(nav_links).to include([ "My credentials", edit_credentials_path ])
    expect(nav_links).to include([ "Templates", cron_templates_path ])
    expect(nav_links).to include([ "Tags", tags_path ])
    active = document.css("nav a").find { |a| a.text.strip == "Tags" }
    expect(active["class"]).to include("border-blue-600")
  end

  it "creates a tag" do
    expect {
      post tags_path, params: { tag: { name: "epic:attachments", color: "indigo" } }
    }.to change { user.tags.count }.by(1)

    expect(user.tags.last.name).to eq("epic:attachments")
    expect(response).to redirect_to(tags_path)
  end

  it "renames and recolors a tag" do
    tag = Factories.tag(user: user, name: "old", color: "gray")

    patch tag_path(tag), params: { tag: { name: "new", color: "green" } }

    expect(tag.reload.name).to eq("new")
    expect(tag.color).to eq("green")
    expect(response).to redirect_to(tags_path)
  end

  it "deletes the tag and its job assignments" do
    repo = Factories.repository(user: user)
    job = Factories.job(repository: repo, issue_number: 7)
    tag = Factories.tag(user: user, name: "doomed", color: "red")
    job.tags << tag

    expect {
      delete tag_path(tag)
    }.to change { JobTag.count }.by(-1)

    expect(Tag.exists?(tag.id)).to be(false)
    expect(response).to redirect_to(tags_path)
  end

  it "keeps legacy mutations inside the legacy fallback" do
    expect {
      post legacy_tags_path, params: { tag: { name: "legacy", color: "gray" } }
    }.to change { user.tags.count }.by(1)
    expect(response).to redirect_to(legacy_tags_path)

    tag = user.tags.last
    patch legacy_tag_path(tag), params: { tag: { name: "legacy-new", color: "blue" } }
    expect(tag.reload.name).to eq("legacy-new")
    expect(response).to redirect_to(legacy_tags_path)

    expect {
      delete legacy_tag_path(tag)
    }.to change { user.tags.count }.by(-1)
    expect(response).to redirect_to(legacy_tags_path)
  end

  it "does not allow managing another user's tags" do
    tag = Factories.tag(user: other, name: "theirs", color: "red")

    patch tag_path(tag), params: { tag: { name: "stolen", color: "blue" } }

    expect(response).to have_http_status(:not_found)
    expect(tag.reload.name).to eq("theirs")
  end
end
