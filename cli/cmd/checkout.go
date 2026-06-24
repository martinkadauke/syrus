package cmd

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

type gitRunner func(ctx context.Context, dir string, args ...string) (string, error)

var checkoutRunGit gitRunner = runGit
var checkoutBackupTimestamp = func() string {
	return time.Now().UTC().Format("20060102T150405Z")
}

func NewCheckoutCommand() *cobra.Command {
	return &cobra.Command{
		Use:           "checkout JOB-ID",
		Short:         "Check out a Syrus Job branch",
		Args:          cobra.ExactArgs(1),
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			jobRef, jobID, err := parseJobRef(args[0])
			if err != nil {
				return err
			}

			client, _, err := apiClient()
			if err != nil {
				return err
			}
			job, err := client.GetJobDetail(cmd.Context(), jobID)
			if err != nil {
				return err
			}
			if strings.TrimSpace(job.Job.BranchName) == "" {
				return fmt.Errorf("Job %s does not have a branch yet (state: %s)", jobRef, job.Job.State)
			}
			if strings.TrimSpace(job.Repository.Slug) == "" {
				return fmt.Errorf("Job %s response did not include a repository slug", jobRef)
			}

			if err := checkoutJobBranch(cmd.Context(), checkoutRunGit, job.Repository.Slug, job.Job.BranchName); err != nil {
				return err
			}
			fmt.Fprintf(cmd.OutOrStdout(), "Checked out %s — run 'syrus test-plan %s' to see the test plan.\n", job.Job.BranchName, jobRef)
			return nil
		},
	}
}

func parseJobRef(input string) (string, string, error) {
	ref := strings.TrimSpace(input)
	if ref == "" {
		return "", "", errors.New("job id is required")
	}
	upper := strings.ToUpper(ref)
	if strings.HasPrefix(upper, "JOB-") {
		id := strings.TrimSpace(ref[4:])
		if id == "" {
			return "", "", fmt.Errorf("invalid job id %q", input)
		}
		return "JOB-" + id, id, nil
	}
	return "JOB-" + ref, ref, nil
}

func checkoutJobBranch(ctx context.Context, runner gitRunner, repoSlug string, branchName string) error {
	inside, err := runner(ctx, "", "rev-parse", "--is-inside-work-tree")
	if err != nil || strings.TrimSpace(inside) != "true" {
		return errors.New("Current directory is not a git repository.")
	}

	remoteURL, err := runner(ctx, "", "remote", "get-url", "origin")
	if err != nil {
		return fmt.Errorf("Could not read git remote origin: %w", err)
	}
	remoteURL = strings.TrimSpace(remoteURL)
	if !remoteMatchesSlug(remoteURL, repoSlug) {
		return fmt.Errorf("Current git remote origin (%s) does not match job repository %s.", remoteURL, repoSlug)
	}

	remoteRef := "refs/remotes/origin/" + branchName
	localRef := "refs/heads/" + branchName

	if _, err := runner(ctx, "", "fetch", "origin", "+refs/heads/"+branchName+":"+remoteRef); err != nil {
		return fmt.Errorf("git fetch failed: %w", err)
	}

	currentBranch, err := runner(ctx, "", "branch", "--show-current")
	currentBranchName := ""
	if err == nil {
		currentBranchName = strings.TrimSpace(currentBranch)
	}

	branchExists := true
	if _, err := runner(ctx, "", "show-ref", "--verify", "--quiet", localRef); err != nil {
		branchExists = false
	}

	if !branchExists {
		if _, err := runner(ctx, "", "checkout", "--track", "-b", branchName, remoteRef); err != nil {
			return fmt.Errorf("git checkout failed: %w", err)
		}
		return nil
	}

	if currentBranchName == branchName {
		status, err := runner(ctx, "", "status", "--porcelain")
		if err != nil {
			return fmt.Errorf("git status failed: %w", err)
		}
		if strings.TrimSpace(status) != "" {
			return fmt.Errorf("cannot update %s because it is currently checked out with local changes; commit or stash them first", branchName)
		}
		if err := backupLocalBranchIfNeeded(ctx, runner, branchName, localRef, remoteRef); err != nil {
			return err
		}
		if _, err := runner(ctx, "", "reset", "--hard", remoteRef); err != nil {
			return fmt.Errorf("git reset failed: %w", err)
		}
		return nil
	}

	if err := backupLocalBranchIfNeeded(ctx, runner, branchName, localRef, remoteRef); err != nil {
		return err
	}
	if _, err := runner(ctx, "", "branch", "-f", branchName, remoteRef); err != nil {
		return fmt.Errorf("git branch update failed: %w", err)
	}
	if _, err := runner(ctx, "", "checkout", branchName); err != nil {
		return fmt.Errorf("git checkout failed: %w", err)
	}
	return nil
}

func backupLocalBranchIfNeeded(ctx context.Context, runner gitRunner, branchName string, localRef string, remoteRef string) error {
	localHead, err := runner(ctx, "", "rev-parse", "--verify", localRef)
	if err != nil {
		return fmt.Errorf("git rev-parse failed for %s: %w", branchName, err)
	}
	remoteHead, err := runner(ctx, "", "rev-parse", "--verify", remoteRef)
	if err != nil {
		return fmt.Errorf("git rev-parse failed for origin/%s: %w", branchName, err)
	}
	if strings.TrimSpace(localHead) == strings.TrimSpace(remoteHead) {
		return nil
	}
	if _, err := runner(ctx, "", "merge-base", "--is-ancestor", localRef, remoteRef); err == nil {
		return nil
	}

	backupName := "syrus/backup/" + sanitizeBranchForBackup(branchName) + "-" + checkoutBackupTimestamp()
	if _, err := runner(ctx, "", "branch", backupName, localRef); err != nil {
		return fmt.Errorf("git backup branch failed: %w", err)
	}
	return nil
}

func sanitizeBranchForBackup(branchName string) string {
	value := strings.NewReplacer(
		"/", "-",
		"\\", "-",
		" ", "-",
		"~", "-",
		"^", "-",
		":", "-",
		"?", "-",
		"*", "-",
		"[", "-",
		"]", "-",
	).Replace(strings.TrimSpace(branchName))
	value = strings.Trim(value, "-")
	if value == "" {
		return "branch"
	}
	return value
}

func runGit(ctx context.Context, dir string, args ...string) (string, error) {
	command := exec.CommandContext(ctx, "git", args...)
	command.Dir = dir
	output, err := command.CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(output))
		if message != "" {
			return string(output), fmt.Errorf("%w: %s", err, message)
		}
		return string(output), err
	}
	return string(output), nil
}

func remoteMatchesSlug(remoteURL string, repoSlug string) bool {
	return strings.EqualFold(normalizeGitRemote(remoteURL), strings.TrimSuffix(repoSlug, ".git"))
}

func normalizeGitRemote(remoteURL string) string {
	value := strings.TrimSpace(remoteURL)
	value = strings.TrimSuffix(value, ".git")

	for _, prefix := range []string{
		"https://github.com/",
		"http://github.com/",
		"ssh://git@github.com/",
		"git://github.com/",
	} {
		if strings.HasPrefix(value, prefix) {
			return strings.TrimPrefix(value, prefix)
		}
	}

	if strings.HasPrefix(value, "git@github.com:") {
		return strings.TrimPrefix(value, "git@github.com:")
	}

	return value
}
