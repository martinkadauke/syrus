// Test builds (X.Y.Z-test.N, built by .github/workflows/test-release.yml) are
// pinned evaluations of unmerged work. They are signed and carry the SAME
// baked-in GitHub Releases feed as a real build (electron-builder writes
// app-update.yml regardless of --publish never), and semver orders
// X.Y.Z-test.N BELOW the X.Y.Z release — so an armed updater would silently
// replace a test install with the next published release mid-evaluation.
// appUpdates.ts therefore never self-updates a test build; graduating to a
// release is a deliberate manual reinstall.
//
// Electron-free (like selfInstall.ts's pure helpers) so the renderer test
// suite can exercise it: desktop/src/pinnedTestBuild.test.ts.
export const isPinnedTestBuild = (version: string): boolean => /-test\.\d+$/.test(version)
