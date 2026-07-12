package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestProfileFromArgv0(t *testing.T) {
	cases := map[string]string{
		"syrus":                          "",
		"/usr/local/bin/syrus":           "",
		"syrus.exe":                      "",
		"C:\\Program Files\\syrus.exe":   "",
		"syrus-test":                     "test",
		"/home/me/.local/bin/syrus-test": "test",
		"syrus-test.exe":                 "test",
		"SYRUS-TEST":                     "test", // case-insensitive
		"config.test":                    "",     // a `go test` binary must not trip it
		"cmd.test":                       "",
		"syrus-canary":                   "", // only the exact test name maps today
	}
	for argv0, want := range cases {
		if got := profileFromArgv0(argv0); got != want {
			t.Errorf("profileFromArgv0(%q) = %q; want %q", argv0, got, want)
		}
	}
}

func TestNormalizeProfile(t *testing.T) {
	cases := map[string]string{
		"":           "",
		"  ":         "",
		"stable":     "",
		"Stable":     "",
		"prod":       "",
		"production": "",
		"release":    "",
		"default":    "",
		"test":       "test",
		"TEST":       "test",
		" test ":     "test",
		"canary":     "canary", // unknown values preserved (lowercased)
	}
	for raw, want := range cases {
		if got := normalizeProfile(raw); got != want {
			t.Errorf("normalizeProfile(%q) = %q; want %q", raw, got, want)
		}
	}
}

func TestCredentialsFilename(t *testing.T) {
	if got := credentialsFilename(""); got != "credentials" {
		t.Errorf("credentialsFilename(\"\") = %q; want credentials", got)
	}
	if got := credentialsFilename("test"); got != "credentials.test" {
		t.Errorf("credentialsFilename(test) = %q; want credentials.test", got)
	}
}

func TestProfileResolutionOrder(t *testing.T) {
	// Flag beats env beats argv0. argv0 in `go test` is a *.test binary, which
	// profileFromArgv0 maps to the default channel, so the base case is stable.
	saved := ProfileFlag
	t.Cleanup(func() { ProfileFlag = saved })

	ProfileFlag = ""
	t.Setenv("SYRUS_PROFILE", "")
	if got := Profile(); got != "" {
		t.Errorf("with nothing set, Profile() = %q; want default (empty)", got)
	}

	t.Setenv("SYRUS_PROFILE", "test")
	if got := Profile(); got != "test" {
		t.Errorf("with SYRUS_PROFILE=test, Profile() = %q; want test", got)
	}

	// The flag overrides the env, including overriding back to the default.
	ProfileFlag = "stable"
	if got := Profile(); got != "" {
		t.Errorf("with --profile stable over SYRUS_PROFILE=test, Profile() = %q; want default", got)
	}

	ProfileFlag = "test"
	t.Setenv("SYRUS_PROFILE", "")
	if got := Profile(); got != "test" {
		t.Errorf("with --profile test, Profile() = %q; want test", got)
	}
}

func TestDefaultCredentialsPathHonorsProfile(t *testing.T) {
	saved := ProfileFlag
	t.Cleanup(func() { ProfileFlag = saved })
	t.Setenv("SYRUS_PROFILE", "")

	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatalf("UserHomeDir: %v", err)
	}

	ProfileFlag = ""
	path, err := DefaultCredentialsPath()
	if err != nil {
		t.Fatalf("DefaultCredentialsPath: %v", err)
	}
	if want := filepath.Join(home, ".syrus", "credentials"); path != want {
		t.Errorf("default path = %q; want %q", path, want)
	}

	ProfileFlag = "test"
	path, err = DefaultCredentialsPath()
	if err != nil {
		t.Fatalf("DefaultCredentialsPath: %v", err)
	}
	if want := filepath.Join(home, ".syrus", "credentials.test"); path != want {
		t.Errorf("test path = %q; want %q", path, want)
	}
}
