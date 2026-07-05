package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tkadauke/syrus/cli/internal/config"
)

func writeLoginTestCredentials(t *testing.T, home string) {
	t.Helper()
	if err := config.SaveCredentials(
		filepath.Join(home, ".syrus", "credentials"),
		config.Credentials{URL: "http://localhost:3000", Token: "old-token-loYI"},
	); err != nil {
		t.Fatal(err)
	}
}

func TestLoginPrefillsExistingUrlAndKeepsItOnEnter(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	writeLoginTestCredentials(t, home)

	// Enter keeps the URL; only the fresh token is typed.
	input := strings.NewReader("\nnew-token\n")
	output := &bytes.Buffer{}
	command := NewLoginCommand()
	command.SetIn(input)
	command.SetOut(output)

	if err := command.Execute(); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	prompts := output.String()
	if !strings.Contains(prompts, "Syrus instance URL [http://localhost:3000]:") {
		t.Fatalf("URL prompt should offer the saved default, got %q", prompts)
	}
	if !strings.Contains(prompts, "API token [keep …loYI]:") {
		t.Fatalf("token prompt should offer to keep the saved token, got %q", prompts)
	}
	if strings.Contains(prompts, "old-token-loYI") {
		t.Fatalf("prompt must never echo the full saved token, got %q", prompts)
	}

	contents, err := os.ReadFile(filepath.Join(home, ".syrus", "credentials"))
	if err != nil {
		t.Fatal(err)
	}
	if got := string(contents); got != "url=http://localhost:3000\ntoken=new-token\n" {
		t.Fatalf("credentials file = %q", got)
	}
}

func TestLoginFlagsSkipPrompts(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	output := &bytes.Buffer{}
	command := NewLoginCommand()
	command.SetIn(strings.NewReader(""))
	command.SetOut(output)
	command.SetArgs([]string{"--url", "https://syrus.example.com", "--token", "flag-token"})

	if err := command.Execute(); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	if strings.Contains(output.String(), "Syrus instance URL") {
		t.Fatalf("flags should skip the prompts, got %q", output.String())
	}

	contents, err := os.ReadFile(filepath.Join(home, ".syrus", "credentials"))
	if err != nil {
		t.Fatal(err)
	}
	if got := string(contents); got != "url=https://syrus.example.com\ntoken=flag-token\n" {
		t.Fatalf("credentials file = %q", got)
	}
}
