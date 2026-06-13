package cmd

import (
	"context"
	"errors"
	"net/url"
	"reflect"
	"strconv"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/tkadauke/syrus/cli/internal/api"
)

type fakeInboxClient struct {
	lists          map[string][]api.JobItem
	details        map[string]api.JobDetail
	listFilters    []url.Values
	detailRequests []string
	approved       []string
	retried        []string
}

func (f *fakeInboxClient) ListJobs(_ context.Context, filters url.Values) (api.JobList, error) {
	f.listFilters = append(f.listFilters, filters)
	state := filters.Get("state")
	return api.JobList{Count: len(f.lists[state]), Jobs: f.lists[state]}, nil
}

func (f *fakeInboxClient) GetJobDetail(_ context.Context, id string) (api.JobDetail, error) {
	f.detailRequests = append(f.detailRequests, id)
	return f.details[id], nil
}

func (f *fakeInboxClient) GetJobTranscript(context.Context, string) (api.JobTranscript, error) {
	return api.JobTranscript{}, nil
}

func (f *fakeInboxClient) GetJobDiff(context.Context, string) (api.JobDiff, error) {
	return api.JobDiff{}, nil
}

func (f *fakeInboxClient) ApproveJob(_ context.Context, id string) error {
	f.approved = append(f.approved, id)
	return nil
}

func (f *fakeInboxClient) RetryJob(_ context.Context, id string) error {
	f.retried = append(f.retried, id)
	return nil
}

func TestFetchInboxJobsScopesToRepoAndAttentionStates(t *testing.T) {
	client := &fakeInboxClient{lists: map[string][]api.JobItem{
		"implemented": {{ID: 1, State: "implemented", UpdatedAt: "2026-06-12T10:00:00Z"}},
		"failed":      {{ID: 2, State: "failed", UpdatedAt: "2026-06-12T11:00:00Z"}},
	}}

	jobs, err := fetchInboxJobs(context.Background(), client, "tkadauke/myapp")
	if err != nil {
		t.Fatal(err)
	}
	if got := []int64{jobs[0].ID, jobs[1].ID}; got[0] != 2 || got[1] != 1 {
		t.Fatalf("jobs sorted by updated_at desc = %v", got)
	}
	if len(client.listFilters) != 2 {
		t.Fatalf("ListJobs called %d times, want 2", len(client.listFilters))
	}
	for _, filters := range client.listFilters {
		if filters.Get("repo") != "tkadauke/myapp" {
			t.Fatalf("repo filter = %q", filters.Get("repo"))
		}
		if filters.Get("state") != "implemented" && filters.Get("state") != "failed" {
			t.Fatalf("unexpected state filter %q", filters.Get("state"))
		}
	}
}

func TestInboxApproveMarksRowHandledAfterConfirmation(t *testing.T) {
	client := &fakeInboxClient{lists: map[string][]api.JobItem{}}
	model := newInboxModel(client, inboxOptions{})
	model.jobs = []api.JobItem{{ID: 456, State: "implemented", Title: "Add dark mode"}}

	updated, cmd := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("a")})
	model = updated.(inboxModel)
	if model.confirm != "approve" || model.pendingID != 456 {
		t.Fatalf("confirm = %q pendingID = %d", model.confirm, model.pendingID)
	}

	updated, cmd = model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("y")})
	model = updated.(inboxModel)
	msg := cmd().(inboxActionMsg)
	if msg.err != nil {
		t.Fatal(msg.err)
	}
	if got := client.approved; len(got) != 1 || got[0] != "456" {
		t.Fatalf("approved = %v", got)
	}

	updated, _ = model.Update(msg)
	model = updated.(inboxModel)
	if len(model.jobs) != 1 {
		t.Fatalf("jobs after approve = %v", model.jobs)
	}
	if model.handled[456] != "approve" {
		t.Fatalf("handled marker = %q", model.handled[456])
	}
	if !strings.Contains(model.View(), "done: approved") {
		t.Fatalf("view does not show handled marker:\n%s", model.View())
	}
}

func TestInboxRefreshPreservesExistingOrderAndHandledRows(t *testing.T) {
	model := newInboxModel(&fakeInboxClient{}, inboxOptions{})
	model.jobs = []api.JobItem{
		{ID: 1, State: "implemented", Title: "First"},
		{ID: 2, State: "failed", Title: "Second"},
	}
	model.handled[1] = "approve"

	updated, _ := model.Update(inboxRefreshMsg{jobs: []api.JobItem{
		{ID: 3, State: "implemented", Title: "Third"},
		{ID: 2, State: "failed", Title: "Second refreshed"},
	}})
	model = updated.(inboxModel)

	var ids []int64
	for _, job := range model.jobs {
		ids = append(ids, job.ID)
	}
	if want := []int64{1, 2, 3}; !reflect.DeepEqual(ids, want) {
		t.Fatalf("ids after refresh = %v, want %v", ids, want)
	}
	if model.jobs[1].Title != "Second refreshed" {
		t.Fatalf("existing row did not refresh: %q", model.jobs[1].Title)
	}
	if model.handled[1] != "approve" {
		t.Fatalf("handled row lost marker")
	}
}

func TestInboxOpenDetailShowsLoadingBeforeFetchCompletes(t *testing.T) {
	model := newInboxModel(&fakeInboxClient{}, inboxOptions{})
	model.jobs = []api.JobItem{{ID: 12, State: "implemented", Title: "Summarize me"}}

	updated, cmd := model.Update(tea.KeyMsg{Type: tea.KeyEnter})
	model = updated.(inboxModel)

	if cmd == nil {
		t.Fatalf("expected detail fetch command")
	}
	if !strings.Contains(model.View(), "Loading details...") {
		t.Fatalf("view does not show loading detail state:\n%s", model.View())
	}
	if strings.Contains(model.View(), "No summary captured yet.") {
		t.Fatalf("view shows empty summary before detail fetch completes:\n%s", model.View())
	}
}

func TestInboxFetchesDetailWhenSelectionChangesWithPanelOpen(t *testing.T) {
	client := &fakeInboxClient{details: map[string]api.JobDetail{
		"2": {Summary: &api.JobSummary{Text: "Second job summary"}},
	}}
	model := newInboxModel(client, inboxOptions{})
	model.jobs = []api.JobItem{
		{ID: 1, State: "implemented", Title: "First"},
		{ID: 2, State: "implemented", Title: "Second"},
	}
	model.detailOpen = true
	model.details[1] = "First job summary"
	model.detailDone[1] = true

	updated, cmd := model.Update(tea.KeyMsg{Type: tea.KeyDown})
	model = updated.(inboxModel)

	if model.cursor != 1 {
		t.Fatalf("cursor = %d, want 1", model.cursor)
	}
	if cmd == nil {
		t.Fatalf("expected detail fetch command")
	}
	msg := cmd().(inboxDetailMsg)
	if msg.err != nil {
		t.Fatal(msg.err)
	}
	updated, _ = model.Update(msg)
	model = updated.(inboxModel)

	if !reflect.DeepEqual(client.detailRequests, []string{"2"}) {
		t.Fatalf("detail requests = %v", client.detailRequests)
	}
	if !strings.Contains(model.View(), "Second job summary") {
		t.Fatalf("view does not show fetched detail:\n%s", model.View())
	}
}

func TestInboxRetryOnlyAppliesToFailedJobs(t *testing.T) {
	client := &fakeInboxClient{}
	model := newInboxModel(client, inboxOptions{})
	model.jobs = []api.JobItem{{ID: 7, State: "implemented"}, {ID: 8, State: "failed"}}

	updated, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("r")})
	model = updated.(inboxModel)
	if model.confirm != "" {
		t.Fatalf("unexpected retry confirmation for implemented job")
	}

	model.cursor = 1
	updated, cmd := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("r")})
	model = updated.(inboxModel)
	if model.confirm != "retry" || model.pendingID != 8 {
		t.Fatalf("confirm = %q pendingID = %d", model.confirm, model.pendingID)
	}
	updated, cmd = model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("y")})
	model = updated.(inboxModel)
	msg := cmd().(inboxActionMsg)
	if msg.err != nil {
		t.Fatal(msg.err)
	}
	if got := client.retried; len(got) != 1 || got[0] != strconv.Itoa(8) {
		t.Fatalf("retried = %v", got)
	}
}

func TestInboxActionErrorKeepsRow(t *testing.T) {
	model := newInboxModel(&fakeInboxClient{}, inboxOptions{})
	model.jobs = []api.JobItem{{ID: 9, State: "implemented"}}

	updated, _ := model.Update(inboxActionMsg{jobID: 9, kind: "approve", handled: true, err: errors.New("nope")})
	model = updated.(inboxModel)

	if len(model.jobs) != 1 {
		t.Fatalf("jobs removed on error")
	}
	if model.err != "nope" {
		t.Fatalf("err = %q", model.err)
	}
}

func TestDetailPanelTextPrefersTestPlanArtifact(t *testing.T) {
	detail := api.JobDetail{
		Summary: &api.JobSummary{Text: "Implemented the switch."},
		Workflows: []api.WorkflowBrief{{
			Artifacts: map[string]any{
				"pr_body": "Adds a switch.\n\n## Test plan\n1. Open settings\n2. Toggle it\n\n## Notes\nNone",
			},
		}},
	}

	got := detailPanelText(detail)
	want := "Test plan:\n1. Open settings\n2. Toggle it"
	if got != want {
		t.Fatalf("detailPanelText = %q, want %q", got, want)
	}
}
