package cmd

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/tkadauke/syrus/cli/internal/api"
	"github.com/tkadauke/syrus/cli/internal/config"
)

var jobSlugPattern = regexp.MustCompile(`(?i)^JOB-(\d+)$`)

type adminJobPayload struct {
	ID         int               `json:"id"`
	IssueTitle string            `json:"issue_title"`
	Workflows  []workflowPayload `json:"workflows"`
}

type workflowPayload struct {
	ID         int                        `json:"id"`
	State      string                     `json:"state"`
	FinishedAt string                     `json:"finished_at"`
	CreatedAt  string                     `json:"created_at"`
	Artifacts  map[string]json.RawMessage `json:"artifacts"`
}

type testPlanArtifact struct {
	Steps []string `json:"steps"`
	Notes string   `json:"notes"`
}

func NewTestPlanCommand() *cobra.Command {
	return &cobra.Command{
		Use:           "test-plan JOB-ID",
		Short:         "Print the latest completed Job test plan",
		Args:          cobra.ExactArgs(1),
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runTestPlan(cmd.Context(), args[0], cmd.OutOrStdout())
		},
	}
}

func parseJobID(slug string) (string, error) {
	matches := jobSlugPattern.FindStringSubmatch(slug)
	if matches == nil {
		return "", errors.New("job must use JOB-<id> format")
	}

	return matches[1], nil
}

func runTestPlan(ctx context.Context, slug string, stdout io.Writer) error {
	jobID, err := parseJobID(slug)
	if err != nil {
		return err
	}

	creds, err := config.LoadDefaultCredentials()
	if err != nil {
		if errors.Is(err, config.ErrMissingCredentials) || errors.Is(err, config.ErrIncompleteCredentials) {
			return errors.New(loginMessage)
		}
		return err
	}

	client, err := api.NewClient(creds.URL, creds.Token)
	if err != nil {
		return err
	}

	payload, err := fetchAdminJob(ctx, client, jobID)
	if err != nil {
		return err
	}

	plan, ok := latestCompletedTestPlan(payload.Workflows)
	if !ok {
		fmt.Fprintf(stdout, "No test plan available for JOB-%s yet — the job may still be implementing.\n", jobID)
		return nil
	}

	printTestPlan(stdout, payload, plan)
	return nil
}

func fetchAdminJob(ctx context.Context, client *api.Client, jobID string) (adminJobPayload, error) {
	raw, err := client.GetAdminJobRaw(ctx, jobID)
	if err != nil {
		return adminJobPayload{}, err
	}

	var payload adminJobPayload
	if err := json.Unmarshal(raw, &payload); err != nil {
		return adminJobPayload{}, err
	}

	return payload, nil
}

func latestCompletedTestPlan(workflows []workflowPayload) (testPlanArtifact, bool) {
	var newest workflowPayload
	var plan testPlanArtifact
	found := false

	for _, workflow := range workflows {
		if !terminalWorkflowState(workflow.State) {
			continue
		}

		rawPlan, ok := workflow.Artifacts["test_plan"]
		if !ok || len(rawPlan) == 0 || string(rawPlan) == "null" {
			continue
		}

		var candidate testPlanArtifact
		if err := json.Unmarshal(rawPlan, &candidate); err != nil {
			continue
		}
		if len(candidate.Steps) == 0 {
			continue
		}

		if !found || workflowAfter(workflow, newest) {
			newest = workflow
			plan = candidate
			found = true
		}
	}

	return plan, found
}

func terminalWorkflowState(state string) bool {
	switch state {
	case "succeeded", "failed", "cancelled":
		return true
	default:
		return false
	}
}

func workflowAfter(left workflowPayload, right workflowPayload) bool {
	leftFinished := parseAPITime(left.FinishedAt)
	rightFinished := parseAPITime(right.FinishedAt)
	if !leftFinished.Equal(rightFinished) {
		return leftFinished.After(rightFinished)
	}

	leftCreated := parseAPITime(left.CreatedAt)
	rightCreated := parseAPITime(right.CreatedAt)
	if !leftCreated.Equal(rightCreated) {
		return leftCreated.After(rightCreated)
	}

	return left.ID > right.ID
}

func parseAPITime(value string) time.Time {
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return time.Time{}
	}

	return parsed
}

func printTestPlan(stdout io.Writer, payload adminJobPayload, plan testPlanArtifact) {
	fmt.Fprintf(stdout, "Test plan for JOB-%d: %s\n\n", payload.ID, payload.IssueTitle)
	for index, step := range plan.Steps {
		fmt.Fprintf(stdout, "%d. %s\n", index+1, step)
	}

	notes := strings.TrimSpace(plan.Notes)
	if notes == "" {
		return
	}

	fmt.Fprintf(stdout, "\nNotes: %s\n", notes)
}
