package cmd

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPlanFetchesAdminJobAndPrintsNewestCompletedPlan(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	var stdout bytes.Buffer
	var requestedURL string
	var requestedToken string
	payload := `{
		"id": 456,
		"issue_title": "Add user avatar upload",
		"workflows": [
			{
				"id": 1,
				"state": "succeeded",
				"finished_at": "2026-06-10T10:00:00Z",
				"created_at": "2026-06-10T09:00:00Z",
				"artifacts": {
					"test_plan": {
						"steps": ["Old step"],
						"notes": "Old notes."
					}
				}
			},
			{
				"id": 2,
				"state": "running",
				"finished_at": null,
				"created_at": "2026-06-11T09:00:00Z",
				"artifacts": {
					"test_plan": {
						"steps": ["Ignore running workflow"],
						"notes": null
					}
				}
			},
			{
				"id": 3,
				"state": "succeeded",
				"finished_at": "2026-06-11T10:00:00Z",
				"created_at": "2026-06-11T09:00:00Z",
				"artifacts": {
					"test_plan": {
						"steps": [
							"Navigate to /settings/profile",
							"Click \"Upload avatar\" and select a PNG under 2 MB",
							"Verify the avatar appears in the nav bar immediately"
						],
						"notes": "Avatar storage uses ActiveStorage."
					}
				}
			}
		]
	}`

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
		requestedURL = request.URL.String()
		requestedToken = request.Header.Get("Authorization")
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(payload))
	}))
	defer server.Close()
	writeTestCredentials(t, home, server.URL)

	command := NewTestPlanCommand()
	command.SetOut(&stdout)
	command.SetArgs([]string{"JOB-456"})

	if err := command.Execute(); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if requestedURL != "/api/v1/admin/jobs/456" {
		t.Fatalf("unexpected request URL: %s", requestedURL)
	}
	if requestedToken != "Bearer secret-token" {
		t.Fatalf("unexpected authorization header: %s", requestedToken)
	}

	expected := `Test plan for JOB-456: Add user avatar upload

1. Navigate to /settings/profile
2. Click "Upload avatar" and select a PNG under 2 MB
3. Verify the avatar appears in the nav bar immediately

Notes: Avatar storage uses ActiveStorage.
`
	if stdout.String() != expected {
		t.Fatalf("unexpected output:\n%s", stdout.String())
	}
}

func TestPlanPrintsPendingMessageWhenNoCompletedWorkflowHasPlan(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	var stdout bytes.Buffer
	payload := `{
		"id": 456,
		"issue_title": "Add user avatar upload",
		"workflows": [
			{"id": 1, "state": "running", "artifacts": {"test_plan": {"steps": ["Run smoke test"]}}},
			{"id": 2, "state": "succeeded", "artifacts": {}}
		]
	}`

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(payload))
	}))
	defer server.Close()
	writeTestCredentials(t, home, server.URL)

	command := NewTestPlanCommand()
	command.SetOut(&stdout)
	command.SetArgs([]string{"JOB-456"})

	if err := command.Execute(); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	expected := "No test plan available for JOB-456 yet — the job may still be implementing.\n"
	if stdout.String() != expected {
		t.Fatalf("unexpected output: %q", stdout.String())
	}
}

func TestPlanRequiresJobSlug(t *testing.T) {
	var stderr bytes.Buffer
	command := NewTestPlanCommand()
	command.SetErr(&stderr)
	command.SetArgs([]string{"456"})

	err := command.Execute()
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "job must use JOB-<id> format") {
		t.Fatalf("unexpected error: %s", err)
	}
}
