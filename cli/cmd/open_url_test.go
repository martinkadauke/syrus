package cmd

import (
	"reflect"
	"testing"
)

func TestOpenURLCommandLinePerGOOS(t *testing.T) {
	target := "https://example.com/pr/1?tab=files&foo=100%25"

	tests := []struct {
		goos     string
		wantName string
		wantArgs []string
	}{
		{goos: "darwin", wantName: "open", wantArgs: []string{target}},
		{goos: "windows", wantName: "rundll32", wantArgs: []string{"url.dll,FileProtocolHandler", target}},
		{goos: "linux", wantName: "xdg-open", wantArgs: []string{target}},
		{goos: "freebsd", wantName: "xdg-open", wantArgs: []string{target}},
	}

	for _, tt := range tests {
		t.Run(tt.goos, func(t *testing.T) {
			name, args := openURLCommandLine(tt.goos, target)
			if name != tt.wantName {
				t.Errorf("name = %q, want %q", name, tt.wantName)
			}
			if !reflect.DeepEqual(args, tt.wantArgs) {
				t.Errorf("args = %v, want %v", args, tt.wantArgs)
			}
		})
	}
}

func TestOpenURLCommandLineWindowsAvoidsCmdParsing(t *testing.T) {
	// URLs with cmd.exe metacharacters must pass through untouched — the
	// whole point of the rundll32 branch is that nothing re-parses the URL.
	target := "https://example.com/search?q=a&b=c^d%20e"
	name, args := openURLCommandLine("windows", target)
	if name == "cmd" {
		t.Fatal("windows opener must not route through cmd.exe")
	}
	if args[len(args)-1] != target {
		t.Fatalf("target mangled: %q", args[len(args)-1])
	}
}
