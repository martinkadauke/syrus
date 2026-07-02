# frozen_string_literal: true

require "open3"
require "rails_helper"

RSpec.describe "bin/syrus-mcp-sidecar" do
  let(:root) { Rails.root.to_s }

  it "does not activate date before Bundler selects the application bundle" do
    script = <<~RUBY
      begin
        load "bin/syrus-mcp-sidecar"
      rescue SystemExit
      end

      abort "date activated before Bundler setup" if Gem.loaded_specs.key?("date")
      %w[BUNDLE_APP_CONFIG BUNDLE_USER_HOME BUNDLE_USER_CACHE BUNDLE_BIN_PATH RUBYOPT].each do |key|
        abort "\#{key} leaked into sidecar boot" if ENV.key?(key)
      end
    RUBY

    _stdout, stderr, status = Open3.capture3(
      {
        "HOME" => ENV.fetch("HOME"),
        "PATH" => ENV.fetch("PATH"),
        "TMPDIR" => ENV["TMPDIR"],
        "BUNDLE_APP_CONFIG" => "/workspace/.syrus/deps/bundle-config",
        "BUNDLE_USER_HOME" => "/workspace/.syrus/deps/bundle-home",
        "BUNDLE_USER_CACHE" => "/workspace/.syrus/deps/bundle-cache",
        "BUNDLE_BIN_PATH" => "/workspace/.syrus/deps/bundle/bin/bundle",
        "RUBYOPT" => "-W0"
      }.compact,
      RbConfig.ruby,
      "-e",
      script,
      chdir: root,
      unsetenv_others: true
    )

    expect(status).to be_success, stderr
  end
end
