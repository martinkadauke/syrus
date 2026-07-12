package config

import (
	"os"
	"strings"
)

// ProfileFlag is bound to the root command's --profile persistent flag. Empty
// means "not passed on the command line"; resolution then falls through to the
// SYRUS_PROFILE env var and finally the name the binary was invoked as.
var ProfileFlag string

// TestProfile is the one non-default channel today: a `syrus-test` binary
// (installed beside `syrus` by a test build of the desktop app) targets the
// test backend and reads ~/.syrus/credentials.test.
const TestProfile = "test"

// Profile resolves which channel this invocation targets. Order, highest
// first: the --profile flag, the SYRUS_PROFILE env var, then the basename the
// binary was invoked as (`syrus-test` -> "test"). The empty string is the
// stable/default channel. Keeping argv[0] last means one Go artifact behaves
// correctly under either name — there is no per-channel CLI build.
func Profile() string {
	// A source counts as "set" when it carries any non-blank value — even one
	// that normalizes to the default channel. That is what lets an explicit
	// `--profile stable` override an inherited SYRUS_PROFILE=test instead of
	// silently falling through to it.
	if strings.TrimSpace(ProfileFlag) != "" {
		return normalizeProfile(ProfileFlag)
	}
	if env := os.Getenv("SYRUS_PROFILE"); strings.TrimSpace(env) != "" {
		return normalizeProfile(env)
	}
	return profileFromArgv0(os.Args[0])
}

// normalizeProfile folds the several spellings of "the default channel" to ""
// and lowercases everything else. An unrecognized value is preserved (it just
// selects ~/.syrus/credentials.<value>, which won't exist until `syrus login`).
func normalizeProfile(raw string) string {
	switch v := strings.ToLower(strings.TrimSpace(raw)); v {
	case "", "stable", "prod", "production", "release", "default":
		return ""
	default:
		return v
	}
}

// profileFromArgv0 maps the invoked binary name to a profile. Only the exact
// `syrus-test` name (with an optional .exe on Windows) selects the test
// channel; a `go test` binary such as `config.test` ends in ".test", not
// "-test", so it correctly stays on the default channel.
func profileFromArgv0(argv0 string) string {
	// Strip the directory using BOTH separators. filepath.Base only splits on
	// the HOST separator, so on a Linux/darwin CI runner it would not split a
	// Windows-style "C:\...\syrus-test.exe" argv0 — leaving the whole path and
	// silently missing the test profile on the very platform a test build ships
	// to. Splitting on / and \ keeps this correct (and portably testable) on
	// every OS.
	base := argv0
	if i := strings.LastIndexAny(base, `/\`); i >= 0 {
		base = base[i+1:]
	}
	base = strings.ToLower(base)
	base = strings.TrimSuffix(base, ".exe")
	if base == "syrus-"+TestProfile {
		return TestProfile
	}
	return ""
}

// credentialsFilename is the basename inside ~/.syrus for a given profile:
// "credentials" for the default channel, "credentials.<profile>" otherwise.
func credentialsFilename(profile string) string {
	if profile == "" {
		return "credentials"
	}
	return "credentials." + profile
}
