# frozen_string_literal: true

require "yaml"
require "spec_helper"

# The TEST BUILD pipeline (.github/workflows/test-build.yml). Its contract
# is the inverse of release.yml's: every component is DETERMINISTICALLY built —
# the backend image is pushed to GHCR under a collision-proof test tag, and the
# signed installers pin that exact tag — while publishing is structurally
# impossible (contents: read, no gh release, :latest untouched). The invariants
# here are the ones that would quietly turn a test build into a shadow release
# (or a broken artifact) if broken.
RSpec.describe "desktop test-build pipeline" do
  let(:repo_root) { File.expand_path("../..", __dir__) }
  let(:workflow_path) { File.join(repo_root, ".github/workflows/test-build.yml") }
  let(:workflow_text) { File.read(workflow_path, encoding: "UTF-8") }
  let(:workflow) { YAML.safe_load(workflow_text) }

  it "is workflow_dispatch-only, with a deliberately small input surface" do
    # `on:` parses as the boolean key true.
    triggers = workflow[true]
    expect(triggers.keys).to eq(["workflow_dispatch"])
    inputs = triggers.dig("workflow_dispatch", "inputs")
    expect(inputs.keys).to contain_exactly("run_integration_tests", "build_windows")
    expect(inputs.dig("run_integration_tests", "type")).to eq("boolean")
    expect(inputs.dig("run_integration_tests", "default")).to eq(true)
    expect(inputs.dig("build_windows", "type")).to eq("boolean")
    expect(inputs.dig("build_windows", "default")).to eq(true)
  end

  it "makes publishing structurally impossible: contents read-only, no release, no :latest" do
    # contents: read means creating a tag or GitHub Release cannot happen even
    # if a step tried — the strongest "never publishes" guarantee.
    expect(workflow.dig("permissions", "contents")).to eq("read")
    expect(workflow.dig("permissions", "packages")).to eq("write")
    # No release surface at all.
    expect(workflow_text).not_to include("gh release")
    expect(workflow_text).not_to include("--generate-notes")
    # The only imagetools targets are the two guarded test tags (sha +
    # version-named twin) — :latest never moves.
    expect(workflow_text).to match(/imagetools create -t "\$IMAGE:\$VERSION" -t "\$IMAGE:\$VERSION_TAG"/)
    expect(workflow_text).not_to match(/imagetools create[^\n]*:latest/)
    # No publish/publish-website jobs — build jobs only.
    expect(workflow["jobs"].keys).to contain_exactly(
      "prepare", "build-backend", "merge-backend", "build-cli", "build-mac", "build-windows"
    )
  end

  it "keeps test builds off the release concurrency group and supersedes stale runs" do
    expect(workflow.dig("concurrency", "group")).to include("test-build-")
    expect(workflow.dig("concurrency", "cancel-in-progress")).to eq(true)
  end

  it "guards the image tag and app version so they can never collide with a release" do
    # test-<short-sha> for the image; the guard step re-asserts the shape and
    # explicitly rejects `latest` and semver-looking tags.
    expect(workflow_text).to include('image_tag="test-$short_sha"')
    expect(workflow_text).to include('^test-[a-f0-9]{7,}$')
    expect(workflow_text).to include('if [ "$IMAGE_TAG" = "latest" ]')
    expect(workflow_text).to include('"$IMAGE_TAG" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+ ]]')
    # The version-named twin tag is guarded to the test- prefix too, so the
    # badge-consistent tag can also never collide with a release tag.
    expect(workflow_text).to include('version_tag="test-$app_version"')
    expect(workflow_text).to include('^test-[0-9]+\.[0-9]+\.[0-9]+-test\.[0-9]+$')
    # The installers carry a -test.<run-number> prerelease over the next
    # patch, so a test app can never be mistaken for a release. (The reverse
    # direction — a test install never auto-updating ONTO a release — is the
    # appUpdates.ts guard, pinned below.)
    expect(workflow_text).to include('-test.$GITHUB_RUN_NUMBER')
    expect(workflow_text).to include('^[0-9]+\.[0-9]+\.[0-9]+-test\.[0-9]+$')
    # The version base mirrors release.yml's prepare: the HIGHER of the newest
    # release tag and the committed desktop/package.json floor, so test builds
    # stay on the right release line during a planned major/minor bump.
    expect(workflow_text).to include(%q{pkg="$(node -p "require('./desktop/package.json').version")"})
    expect(workflow_text).to include(%q{base="$(printf '%s\n%s\n' "${latest_tag:-0.0.0}" "${pkg%%-*}" | sort -V | tail -1)"})
  end

  it "disarms auto-update in both directions" do
    # Direction 1: release installs never see a test build — nothing here is
    # published to the GitHub Releases feed (permissions + artifact tests
    # above pin that).
    # Direction 2: a test install never replaces ITSELF — a signed test build
    # still carries the baked-in GitHub feed (electron-builder writes
    # app-update.yml regardless of --publish never), and semver orders
    # X.Y.Z-test.N BELOW X.Y.Z, so an armed updater would swap the pinned
    # evaluation for the next published release. The app's updater guard
    # skips auto-update for -test. versions; the classifier's behavior is
    # covered by desktop/src/pinnedTestBuild.test.ts, the wiring is pinned
    # here.
    classifier = File.read(File.join(repo_root, "desktop/electron/pinnedTestBuild.ts"), encoding: "UTF-8")
    expect(classifier).to include('isPinnedTestBuild = (version: string): boolean => /-test\.\d+$/.test(version)')
    app_updates = File.read(File.join(repo_root, "desktop/electron/appUpdates.ts"), encoding: "UTF-8")
    expect(app_updates).to include('import { isPinnedTestBuild } from "./pinnedTestBuild.js"')
    expect(app_updates).to match(/updatesEnabled = \(\)[\s\S]{0,160}!isPinnedTestBuild\(app\.getVersion\(\)\)/)
    expect(File.exist?(File.join(repo_root, "desktop/src/pinnedTestBuild.test.ts"))).to be(true)
  end

  it "builds the backend natively per arch, always pushes by digest, and merges the test tag" do
    # Same native matrix as release.yml — amd64 on ubuntu-latest, arm64 on
    # ubuntu-24.04-arm, NO QEMU.
    expect(workflow_text).to include("ubuntu-24.04-arm")
    expect(workflow_text).not_to include("setup-qemu-action")
    expect(workflow.dig("jobs", "build-backend", "strategy", "matrix", "include")).to be_an(Array)
    # The build goes through bin/publish-image --no-push (integration gate
    # included; run_integration_tests=false maps to its --skip-tests flag).
    expect(workflow_text).to match(/args=\("\$IMAGE_TAG" --no-push\)/)
    expect(workflow_text).to include("--skip-tests")
    # Unlike release.yml there is NO dry_run gate: the by-digest push and the
    # manifest merge are unconditional — uploading the image is the point.
    expect(workflow_text).to include("push-by-digest=true")
    expect(workflow_text).not_to match(/if:.*dry_run/)
    push_step = workflow_text[/name: Push \$\{\{ matrix\.arch \}\} by digest[\s\S]{0,300}/]
    expect(push_step).not_to include("if:")
    expect(workflow.dig("jobs", "merge-backend", "if")).to be_nil
    # The merged manifest is verified pullable through the shared helper.
    expect(workflow_text).to include('syrus_verify_pushed "$IMAGE" "$VERSION"')
    # Test builds write their OWN registry cache refs. bin/publish-image's
    # --cache-to mode=max REPLACES the tag it writes, so pointing a test build
    # at release.yml's shared buildcache-<arch> tags would let a divergent
    # test branch evict the warm cache the next real release depends on.
    expect(workflow_text.scan("ghcr.io/tkadauke/syrus-backend:buildcache-test-${{ matrix.arch }}").size).to eq(2)
    expect(workflow_text).not_to include("syrus-backend:buildcache-${{ matrix.arch }}")
  end

  it "derives SYRUS_BUILT_AT from the source, never the wall clock, in both build and push" do
    # Same deterministic expression as release.yml (HEAD's committer date, UTC)
    # in the publish-image build step AND the by-digest push step, so both
    # arch images and the desktop stamp agree on one instant.
    git_stamp = %q{SYRUS_BUILT_AT="$(TZ=UTC git show -s --format=%cd --date=format-local:'%Y-%m-%dT%H:%M:%SZ' HEAD)"}
    expect(workflow_text.scan(git_stamp).size).to eq(2)
    expect(workflow_text).not_to include('SYRUS_BUILT_AT="$(date')
    expect(workflow_text).not_to include('SYRUS_BUILT_AT=${SYRUS_BUILT_AT:-}')
    # The push rebuild must stay a cache hit of the tested build — identical
    # build args (see release.yml's lockstep rule).
    expect(workflow_text).to include('--build-arg "GIT_SHA=$(git rev-parse --short HEAD)"')
    expect(workflow_text).to include('--build-arg "SYRUS_VERSION=$VERSION"')
    expect(workflow_text).to include('--build-arg "SYRUS_BUILT_AT=$SYRUS_BUILT_AT"')
  end

  it "pins the pushed test image into both installers and verifies the pin" do
    # SYRUS_BACKEND_IMAGE overrides stage-backend-assets.mjs's version-derived
    # pin — without it, SYRUS_RELEASE_BUILD=1 would pin :<app_version>, a tag
    # that never exists. Both desktop build steps must stage it.
    # The manifest pins the VERSION-NAMED tag so the in-app badge reads
    # consistently (app 0.1.4-test.1 · backend test-0.1.4-test.1).
    stage_ref = "SYRUS_BACKEND_IMAGE: ghcr.io/tkadauke/syrus-backend:${{ needs.prepare.outputs.version_tag }}"
    expect(workflow_text.scan(stage_ref).size).to eq(2)
    # Desktop builds in parallel with the backend (needs: prepare) — the pin
    # is a string, not a pull; merge-backend pushes the image concurrently and
    # it exists by run completion. (Parallelism is pinned in its own example.)
    # ...and each verify step asserts the sealed manifest actually carries it.
    expect(workflow_text).to include('grep -qF "\"image\": \"$BACKEND_IMAGE\"" "$APP/Contents/Resources/backend/manifest.json"')
    expect(workflow_text).to include("desktop/out/win-unpacked/resources/backend/manifest.json")
  end

  it "signs test builds exactly like a release (guards, preflights, forced signing)" do
    expect(workflow_text.scan("A signed build is required").length).to be >= 2
    expect(workflow_text.scan("-c.forceCodeSigning=true").length).to be >= 2
    expect(workflow_text).to include("Preflight: Apple signing credentials")
    expect(workflow_text).to include("Preflight: Azure credentials")
    expect(workflow_text).to include("xcrun stapler validate")
    # SYRUS_RELEASE_BUILD arms stage-cli's hard-fail and release DMG naming in
    # both desktop jobs, and Go is pinned so the hard-fail never fires.
    expect(workflow_text.scan('SYRUS_RELEASE_BUILD: "1"').size).to eq(2)
    setup_go = workflow_text.scan(%r{uses: actions/setup-go@\S+\s+with:\s+go-version-file: cli/go\.mod})
    expect(setup_go.length).to eq(3) # build-cli + build-mac + build-windows
    expect(workflow_text.scan("cache-dependency-path: cli/go.sum").size).to eq(3)
    expect(workflow_text).to include("grep -qF 'stage-cli: Go toolchain not found'")
    # Stage only — nothing ever publishes from a build.
    expect(workflow_text).to include("--publish never")
    expect(workflow_text).not_to include("--publish always")
  end

  it "cross-compiles and stages the CLI tarballs like a real release" do
    # The Linux CLI is a shippable component too: bin/release-cli runs
    # `go test ./...`, cross-compiles linux/amd64 + arm64 tarballs, and writes
    # SHA256SUMS-cli.txt. A test build must prove it builds.
    expect(workflow.dig("jobs", "build-cli", "needs")).to eq("prepare")
    expect(workflow_text).to match(%r{run: bin/release-cli "\$TAG"})
    expect(workflow_text).to include("TAG: v${{ needs.prepare.outputs.app_version }}")
    expect(workflow_text).to include("path: dist/releases/v${{ needs.prepare.outputs.app_version }}/cli/")
    # No input gate — release.yml's build-cli is unconditional, so is this.
    expect(workflow.dig("jobs", "build-cli", "if")).to be_nil
  end

  it "uploads versioned artifacts to the run only — no permalinks, no update feed" do
    # The versioned .dmg / Setup .exe / CLI tarballs land as workflow-run
    # artifacts with a 14-day retention and hard-fail if the build produced
    # nothing.
    mac_upload = workflow_text[/name: test-staged-mac[\s\S]{0,200}/]
    expect(mac_upload).to include("if-no-files-found: error")
    expect(mac_upload).to include("retention-days: 14")
    windows_upload = workflow_text[/name: test-staged-windows[\s\S]{0,200}/]
    expect(windows_upload).to include("if-no-files-found: error")
    expect(windows_upload).to include("retention-days: 14")
    cli_upload = workflow_text[/name: test-staged-cli[\s\S]{0,200}/]
    expect(cli_upload).to include("if-no-files-found: error")
    expect(cli_upload).to include("retention-days: 14")
    expect(workflow_text).to match(%r{cp "desktop/out/Syrus-\$VERSION-universal\.dmg" "\$RUNNER_TEMP/staged/"})
    expect(workflow_text).to match(%r{cp "desktop/out/Syrus-Setup-\$VERSION-x64\.exe" "\$RUNNER_TEMP/staged/"})
    # No stable-name aliases (those are the website permalinks — releases only)
    # and no auto-update feed files: a test build must never feed the channel.
    # Assert on the code, not the comments that explain the omission.
    code = workflow_text.lines.reject { |l| l.strip.start_with?("#") }.join
    expect(code).not_to match(%r{staged/Syrus\.dmg})
    expect(code).not_to match(%r{staged/Syrus-Setup\.exe})
    expect(code).not_to include("latest-mac.yml")
    expect(code).not_to include("latest.yml")
    expect(code).not_to include(".blockmap")
  end

  it "never inlines the computed tag/version into shell bodies" do
    # Same rule as release.yml: attacker-influenceable values reach run:
    # bodies only via env, never inline ${{ }} interpolation. Walk the parsed
    # YAML rather than regex-slicing the text so EVERY run: value is covered —
    # single-line runs and folded scalars included, not just literal
    # `run: |` blocks.
    run_bodies = workflow["jobs"].values.flat_map { |job| Array(job["steps"]).map { |step| step["run"] } }.compact
    expect(run_bodies.length).to be >= 15 # every step in the file, not a lucky regex subset
    run_bodies.each do |body|
      expect(body).not_to match(/\$\{\{\s*needs\./)
      expect(body).not_to match(/\$\{\{\s*inputs\./)
    end
  end

  it "documents the test-build runbook next to the release one" do
    runbook = File.read(File.join(repo_root, "docs/releasing.md"), encoding: "UTF-8")
    expect(runbook).to include("test-build.yml")
    expect(runbook).to include("gh workflow run test-build.yml --ref")
    expect(runbook).to include("test-staged-mac")
    expect(runbook).to include("test-staged-windows")
    expect(runbook).to include("test-staged-cli")
    # The tag scheme and retention are the operator-facing contract.
    expect(runbook).to match(/test-<short-sha>|test-<sha>/)
    expect(runbook).to include("14 days")
  end

  it "builds desktop in parallel with the backend (no merge-backend gate)" do
    # The manifest pin is a string match, not a docker pull, so the desktop
    # jobs never need the image to exist yet — gating them on merge-backend
    # serialized ~5 min of pure waiting. Match release.yml: needs: prepare only.
    expect(workflow.dig("jobs", "build-mac", "needs")).to eq("prepare")
    expect(workflow.dig("jobs", "build-windows", "needs")).to eq("prepare")
  end

  # Drift guard: the test build must build every shippable component the SAME
  # way the real release does, or it is testing a different artifact than it
  # will ship. This is the cheap insurance for the deliberate duplication —
  # if a release build step changes, the mirrored test-build step must too.
  it "uses the same load-bearing build commands as release.yml" do
    release = File.read(File.join(repo_root, ".github/workflows/release.yml"), encoding: "UTF-8")
    shared = [
      "bin/publish-image",   # backend image build + integration gate
      "bin/release-cli",     # CLI tarballs
      "npm --prefix desktop run build", # electron-builder DMG/exe
      "imagetools create",   # multi-arch manifest assembly
    ]
    shared.each do |cmd|
      expect(workflow_text).to include(cmd), "test-build.yml missing #{cmd.inspect}"
      expect(release).to include(cmd), "release.yml missing #{cmd.inspect}"
    end
  end
end
