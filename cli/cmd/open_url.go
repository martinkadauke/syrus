package cmd

import (
	"fmt"
	"os/exec"
	"runtime"
	"strings"
)

// openURLCommandLine returns the program name and arguments that open target
// in the user's default browser on the given GOOS. On Windows it deliberately
// avoids `cmd /c start`: cmd.exe re-parses the line, so URLs containing `&`,
// `^`, or `%` get mangled, and `start` treats a quoted first argument as a
// window title. rundll32's FileProtocolHandler takes the URL as a plain
// argument with no shell parsing at all.
func openURLCommandLine(goos string, target string) (string, []string) {
	switch goos {
	case "darwin":
		return "open", []string{target}
	case "windows":
		return "rundll32", []string{"url.dll,FileProtocolHandler", target}
	default:
		return "xdg-open", []string{target}
	}
}

func openURLCommand(target string) *exec.Cmd {
	name, args := openURLCommandLine(runtime.GOOS, target)
	return exec.Command(name, args...)
}

func defaultOpenBrowser(target string) error {
	output, err := openURLCommand(target).CombinedOutput()
	if err != nil {
		return fmt.Errorf("open browser failed: %s", strings.TrimSpace(string(output)))
	}
	return nil
}
