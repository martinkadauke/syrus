require "rails_helper"
require "rake"

RSpec.describe "syrus:prepare_search" do
  before(:all) do
    Rails.application.load_tasks
  end

  before do
    SearchRecord.connection.execute("DROP TABLE IF EXISTS operational_log_fts")
    Rake::Task["syrus:prepare_search"].reenable
  end

  it "creates missing search virtual tables" do
    Rake::Task["syrus:prepare_search"].invoke

    expect(OperationalLogIndex.available?).to be(true)
  end
end
