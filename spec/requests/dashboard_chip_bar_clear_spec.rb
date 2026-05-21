require "rails_helper"

# Server-side coverage for the chip-bar Clear UX. The visual click
# is exercised by the chip-bar JS controller spec; this verifies
# that a GET to dashboard_jobs_path with an empty q tree clears the
# smart-folder filter (no smart_folder_id in the URL) and yields an
# empty chip-bar tree value on the rendered page.
RSpec.describe "Chip-bar Clear on a kanban smart folder", type: :request do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  before do
    sign_in_as(user)
    SmartFolder.ensure_builtins!
  end

  it "clears the smart-folder filter when smart_folder_id is absent and q is the empty tree" do
    inbox = SmartFolder.find_builtin_by_attention("inbox")
    Factories.job(repository: repo, issue_number: 1)
    Factories.job_record(repository: repo, issue_number: 2, state: "closed",
                          closure_reason: "pr_merged", finished_at: Time.current)

    get dashboard_jobs_path, params: { q: "eyJhbmQiOltdfQ", view: "kanban" }

    document = Nokogiri::HTML(response.body)
    expect(document.at_css("[data-chip-bar-tree-value]")["data-chip-bar-tree-value"]).to eq('{"and":[]}')
    inbox_link = document.css("aside a").find { |a| a.text.include?("Inbox") }
    expect(inbox_link["class"]).not_to include("bg-blue-50")
  end

  it "applies the smart folder when smart_folder_id IS present (sanity)" do
    inbox = SmartFolder.find_builtin_by_attention("inbox")
    Factories.job(repository: repo, issue_number: 1)

    get dashboard_jobs_path, params: { smart_folder_id: inbox.id, view: "kanban" }

    document = Nokogiri::HTML(response.body)
    inbox_link = document.css("aside a").find { |a| a.text.include?("Inbox") }
    expect(inbox_link["class"]).to include("bg-blue-50")
  end
end
