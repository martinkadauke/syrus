package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSkillInstallWritesTheClaudeSkill(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	output := &bytes.Buffer{}
	command := NewSkillCommand()
	command.SetOut(output)
	command.SetArgs([]string{"install"})

	if err := command.Execute(); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	target := filepath.Join(home, ".claude", "skills", "syrus", "SKILL.md")
	contents, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}

	skill := string(contents)
	if !strings.HasPrefix(skill, "---\nname: syrus\n") {
		t.Fatalf("skill missing frontmatter: %q", skill[:80])
	}
	for _, fragment := range []string{
		"syrus inbox",
		"syrus checkout JOB-<id>",
		"syrus approve",
		"Only approve when the user",
		"syrus login",
	} {
		if !strings.Contains(skill, fragment) {
			t.Fatalf("skill missing %q", fragment)
		}
	}

	if !strings.Contains(output.String(), target) {
		t.Fatalf("output should name the target path, got %q", output.String())
	}
}

func TestSkillInstallHonorsDirFlagAndOverwrites(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "syrus", "SKILL.md")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte("stale"), 0o644); err != nil {
		t.Fatal(err)
	}

	command := NewSkillCommand()
	command.SetOut(&bytes.Buffer{})
	command.SetArgs([]string{"install", "--dir", dir})

	if err := command.Execute(); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	contents, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	if string(contents) == "stale" {
		t.Fatal("install should overwrite an existing skill file")
	}
}
