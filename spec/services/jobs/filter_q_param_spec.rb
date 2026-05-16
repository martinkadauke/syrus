require "rails_helper"

# Ensures Jobs::Filter.from_params reads the `q=` URL param and
# AND-merges it with both the legacy flat URL params and an active
# SmartFolder's tree.
RSpec.describe Jobs::Filter, ".from_params with q=" do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user, owner: "acme", name: "widgets") }

  def filter_for(params, smart_folder: nil)
    described_class.from_params(params, smart_folder: smart_folder, user: user).to_h
  end

  it "reads q= and treats it as the primary tree when nothing else is set" do
    tree = { "and" => [ { "field" => "state", "op" => "is", "value" => "open" } ] }
    q = Filters::QueryParam.encode(tree)

    expect(filter_for({ q: q })).to eq(tree)
  end

  it "ANDs q= with the active smart folder's tree" do
    SmartFolder.ensure_builtins!
    inbox = SmartFolder.find_builtin_by_attention("inbox")
    extra = { "and" => [ { "field" => "priority", "op" => "is", "value" => "high" } ] }
    q = Filters::QueryParam.encode(extra)

    result = filter_for({ q: q }, smart_folder: inbox)

    expect(result["and"]).to include(
      a_hash_including("field" => "attention", "value" => "inbox"),
      a_hash_including("field" => "priority", "value" => "high")
    )
  end

  it "ANDs q= with legacy flat URL params (state, repo, ...)" do
    q_tree = { "and" => [ { "field" => "title", "op" => "contains", "value" => "auth" } ] }
    q = Filters::QueryParam.encode(q_tree)

    result = filter_for({ q: q, state: "open" })

    expect(result["and"]).to include(
      a_hash_including("field" => "title", "value" => "auth"),
      a_hash_including("field" => "state", "value" => "open")
    )
  end

  it "ignores a malformed q= without raising" do
    expect { filter_for({ q: "not!valid!base64" }) }.not_to raise_error
  end
end
