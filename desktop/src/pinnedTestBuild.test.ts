import { describe, expect, it } from "vitest"
import { isPinnedTestBuild } from "../electron/pinnedTestBuild"

// A test build (X.Y.Z-test.N, built by .github/workflows/test-release.yml) is
// a pinned evaluation of unmerged work. It is signed and carries the SAME
// baked-in GitHub Releases feed as a real build, and semver orders
// X.Y.Z-test.N BELOW the X.Y.Z release — so an armed updater would silently
// replace the test install with the next published release mid-evaluation.
// appUpdates.ts gates updatesEnabled on !isPinnedTestBuild(app.getVersion());
// that wiring (and the workflow's matching -test.<run-number> version scheme)
// is pinned by spec/desktop/test_release_spec.rb. This suite pins the version
// classifier itself.
describe("isPinnedTestBuild", () => {
  it("recognizes the X.Y.Z-test.N test-release version scheme", () => {
    expect(isPinnedTestBuild("1.2.4-test.7")).toBe(true)
    expect(isPinnedTestBuild("0.10.0-test.123")).toBe(true)
  })

  it("leaves releases, pre-releases, and dev builds on the update path", () => {
    expect(isPinnedTestBuild("1.2.3")).toBe(false)
    expect(isPinnedTestBuild("1.2.3-beta.1")).toBe(false)
    expect(isPinnedTestBuild("0.0.0")).toBe(false)
    // Only the exact -test.<number> suffix counts — a hypothetical
    // "-testflight" style prerelease is NOT a pinned test build.
    expect(isPinnedTestBuild("1.2.3-testflight")).toBe(false)
    expect(isPinnedTestBuild("1.2.3-test.1.rc")).toBe(false)
  })
})
