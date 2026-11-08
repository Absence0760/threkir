package internal

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

// fakeSegmentMatch records what the worker handed the Edge Function and
// answers with err.
type fakeSegmentMatch struct {
	payloads []string
	err      error
}

func (f *fakeBackend) InvokeSegmentMatch(_ context.Context, payload json.RawMessage) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.segmentMatch == nil {
		return errors.New("fakeBackend: segment_match not configured")
	}
	f.segmentMatch.payloads = append(f.segmentMatch.payloads, string(payload))
	return f.segmentMatch.err
}

func segmentMatchJob(payload string) *Job {
	return &Job{ID: 41, Kind: "segment_match", Payload: json.RawMessage(payload), Attempts: 1}
}

func TestSegmentMatchHandsThePayloadToTheFunction(t *testing.T) {
	for _, payload := range []string{
		`{"run_id":"5b000000-0000-4000-8000-000000000001"}`,
		`{"segment_id":"5a5a0000-0000-4000-8000-0000000000d1"}`,
		`{"segment_id":"5a5a0000-0000-4000-8000-0000000000d1","after_run_id":"5b000000-0000-4000-8000-000000000001"}`,
	} {
		b := &fakeBackend{segmentMatch: &fakeSegmentMatch{}}
		w := newTestWorker(b, nil)
		w.handle(context.Background(), segmentMatchJob(payload))
		if len(b.segmentMatch.payloads) != 1 || b.segmentMatch.payloads[0] != payload {
			t.Fatalf("payload %s: function got %v", payload, b.segmentMatch.payloads)
		}
		if len(b.finished) != 1 || b.finished[0].Status != "done" {
			t.Fatalf("payload %s: want finish_job(done), got %+v", payload, b.finished)
		}
	}
}

func TestSegmentMatchRefusesAMalformedPayloadWithoutCalling(t *testing.T) {
	for _, payload := range []string{
		`{}`,
		`[]`,
		`{"run_id":"nope"}`,
		`{"run_id":"5B000000-0000-4000-8000-000000000001"}`,
		`{"run_id":"5b000000-0000-4000-8000-000000000001","segment_id":"5a5a0000-0000-4000-8000-0000000000d1"}`,
		`{"run_id":"5b000000-0000-4000-8000-000000000001","after_run_id":"5b000000-0000-4000-8000-000000000002"}`,
		`{"segment_id":"5a5a0000-0000-4000-8000-0000000000d1","after_run_id":7}`,
	} {
		b := &fakeBackend{segmentMatch: &fakeSegmentMatch{}}
		w := newTestWorker(b, nil)
		w.handle(context.Background(), segmentMatchJob(payload))
		if len(b.segmentMatch.payloads) != 0 {
			t.Fatalf("payload %s reached the function", payload)
		}
		if len(b.finished) != 1 || b.finished[0].Status != "failed" {
			t.Fatalf("payload %s: want finish_job(failed), got %+v", payload, b.finished)
		}
	}
}

func TestSegmentMatchRetriesA5xxAndFailsA4xx(t *testing.T) {
	retry := &fakeBackend{segmentMatch: &fakeSegmentMatch{err: &HTTPError{StatusCode: 503}}}
	newTestWorker(retry, nil).handle(context.Background(), segmentMatchJob(`{"run_id":"5b000000-0000-4000-8000-000000000001"}`))
	if len(retry.deferred) != 1 || len(retry.finished) != 0 {
		t.Fatalf("a 503 must defer the job: deferred=%+v finished=%+v", retry.deferred, retry.finished)
	}

	refuse := &fakeBackend{segmentMatch: &fakeSegmentMatch{err: &HTTPError{StatusCode: 400}}}
	newTestWorker(refuse, nil).handle(context.Background(), segmentMatchJob(`{"run_id":"5b000000-0000-4000-8000-000000000001"}`))
	if len(refuse.finished) != 1 || refuse.finished[0].Status != "failed" {
		t.Fatalf("a 400 must fail the job: %+v", refuse.finished)
	}
}

func TestInvokeSegmentMatchPostsToTheFunctionWithTheServerKey(t *testing.T) {
	var gotPath, gotKey, gotAuth, gotBody string
	status := http.StatusOK
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.Method + " " + r.URL.Path
		gotKey = r.Header.Get("apikey")
		gotAuth = r.Header.Get("Authorization")
		body, _ := io.ReadAll(r.Body)
		gotBody = string(body)
		w.WriteHeader(status)
		_, _ = w.Write([]byte(`{"outcome":"recorded","owner":"someone@example.com"}`))
	}))
	defer srv.Close()

	c := NewSupabaseClient(srv.URL+"/", "sb_secret_worker")
	payload := json.RawMessage(`{"run_id":"5b000000-0000-4000-8000-000000000001"}`)
	if err := c.InvokeSegmentMatch(context.Background(), payload); err != nil {
		t.Fatalf("2xx must be nil, got %v", err)
	}
	if gotPath != "POST /functions/v1/segment-match" || gotKey != "sb_secret_worker" || gotAuth != "" || gotBody != string(payload) {
		t.Fatalf("request = %q key=%q auth=%q body=%q", gotPath, gotKey, gotAuth, gotBody)
	}

	status = http.StatusServiceUnavailable
	err := c.InvokeSegmentMatch(context.Background(), payload)
	var hErr *HTTPError
	if !errors.As(err, &hErr) || hErr.StatusCode != 503 || !isTransient(err) {
		t.Fatalf("a 503 must be a transient *HTTPError, got %v", err)
	}
	if want := "supabase http 503 (Service Unavailable): POST /functions/v1/segment-match"; err.Error() != want {
		t.Fatalf("error text %q must not carry the body", err.Error())
	}
}
