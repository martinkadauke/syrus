# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe "bin/build-local-image" do
  let(:script_path) { File.expand_path("../../bin/build-local-image", __dir__) }
  let(:script) { File.read(script_path, encoding: "UTF-8") }
  let(:lib) { File.read(File.expand_path("../../bin/docker-image-lib", __dir__), encoding: "UTF-8") }
  let(:compose_up) { File.read(File.expand_path("../../bin/compose-up", __dir__), encoding: "UTF-8") }

  it "passes a bash syntax check" do
    _out, err, status = Open3.capture3("bash", "-n", script_path)
    expect(status.exitstatus).to eq(0), err
  end

  it "is executable" do
    expect(File.executable?(script_path)).to be(true)
  end

  it "builds through the shared docker-image-lib helper, not a copied build block" do
    expect(script).to include(". bin/docker-image-lib")
    expect(script).to include("syrus_build_local_backend_image")
    expect(script).not_to include("docker buildx build")
  end

  it "defaults the tag to the working tree's short sha under the syrus-local repo" do
    # The tag must NOT be a published registry ref: the desktop installer
    # pulls whatever manifest.json names, and a successful pull would clobber
    # the local build. An unpublished local tag makes the pull fail and
    # install.sh fall back to the local image.
    expect(script).to include('TAG="${1:-dev-${GIT_SHA}}"')
    expect(script).to include('IMAGE="syrus-local:${TAG}"')
  end

  it "prints the SYRUS_BACKEND_IMAGE staging hint for the desktop build" do
    expect(script).to include("SYRUS_BACKEND_IMAGE=${IMAGE} npm --prefix desktop run build")
  end

  it "shares the base-image build with bin/compose-up via the lib" do
    expect(lib).to include("syrus_build_local_base_image()")
    expect(lib).to include("syrus_build_local_backend_image()")
    expect(compose_up).to include("syrus_build_local_base_image dev")
    # The historical compose-up behavior — writing the registry cache back —
    # survives the refactor as the opt-out SYRUS_DOCKER_CACHE_PUSH default.
    expect(compose_up).to include('SYRUS_DOCKER_CACHE_PUSH="${SYRUS_DOCKER_CACHE_PUSH:-1}"')
    expect(compose_up).not_to include("--cache-to")
  end

  it "keeps the Dockerfile.local overlay as the final image layer" do
    expect(lib).to match(/docker build -f Dockerfile\.local[\s\S]{0,120}BASE_IMAGE=syrus-local-base:latest/)
  end
end
