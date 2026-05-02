require "vcr"
require "webmock/rspec"

VCR.configure do |c|
  c.cassette_library_dir = Rails.root.join("spec/cassettes")
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.filter_sensitive_data("<GITHUB_TOKEN>") { "ghp_test_token" }
  c.default_cassette_options = { record: :none, match_requests_on: [ :method, :host, :path ] }
end

RSpec.configure do |config|
  WebMock.disable_net_connect!(allow_localhost: true)
end
