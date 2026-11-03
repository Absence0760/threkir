package livehub

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// capturedInsert records one InsertLivePing call.
type capturedInsert struct {
	runID  string
	userID string
	ping   Ping
}

// fakePersister signals each InsertLivePing on a channel so a test can
// wait for the detached persist goroutine deterministically.
type fakePersister struct {
	ch  chan capturedInsert
	err error
}

func newFakePersister() *fakePersister {
	return &fakePersister{ch: make(chan capturedInsert, 4)}
}

func (f *fakePersister) InsertLivePing(_ context.Context, runID, userID string, p Ping) error {
	f.ch <- capturedInsert{runID: runID, userID: userID, ping: p}
	return f.err
}

// pushOK POSTs a ping and asserts a 202. Returns nothing; fatals on
// mismatch.
func pushOK(t *testing.T, base, runID, body string) {
	t.Helper()
	resp, err := http.Post(base+"/v1/live/"+runID+"/push", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("push status=%d, want 202", resp.StatusCode)
	}
}

func newPersistServer(t *testing.T, srv *Server) (string, func()) {
	t.Helper()
	if srv.Hub == nil {
		srv.Hub = NewHub()
	}
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)
	ts := httptest.NewServer(mux)
	return ts.URL, ts.Close
}

func TestPersist_MirrorsAcceptedPushToLiveRunPings(t *testing.T) {
	persister := newFakePersister()
	meta := &fakeRunMetaFetcher{rows: map[string]*RunMeta{"run-1": {UserID: "user-A", IsPublic: true}}}
	consent := &fakeHeartRateConsent{shared: map[string]bool{"user-A": true}}
	base, teardown := newPersistServer(t, &Server{Persister: persister, RunMeta: meta, HeartRate: consent})
	defer teardown()

	pushOK(t, base, "run-1", `{"lat":51.5,"lng":-0.1,"distance_m":500,"elapsed_s":120,"bpm":150,"ele":42.5}`)

	select {
	case got := <-persister.ch:
		if got.runID != "run-1" || got.userID != "user-A" {
			t.Fatalf("insert run/user = %q/%q, want run-1/user-A", got.runID, got.userID)
		}
		if got.ping.Lat != 51.5 || got.ping.Lng != -0.1 || got.ping.DistanceM != 500 || got.ping.ElapsedS != 120 {
			t.Fatalf("ping core fields not carried: %+v", got.ping)
		}
		if got.ping.BPM == nil || *got.ping.BPM != 150 || got.ping.Elevation == nil || *got.ping.Elevation != 42.5 {
			t.Fatalf("ping optional fields not carried: %+v", got.ping)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("push did not trigger a live_run_pings persist within the deadline")
	}
}

func TestPersist_SkippedWhenNotWired(t *testing.T) {
	// No Persister / RunMeta — the hub stays fan-out-only (pre-bridge
	// behaviour). A push still succeeds and, importantly, doesn't panic
	// on the nil persist path.
	base, teardown := newPersistServer(t, &Server{})
	defer teardown()
	pushOK(t, base, "run-1", `{"lat":1,"lng":2,"distance_m":0,"elapsed_s":0}`)
	// Snapshot confirms the fan-out path still worked.
	resp, err := http.Get(base + "/v1/live/run-1/snapshot")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("snapshot status=%d, want 200 (fan-out unaffected)", resp.StatusCode)
	}
}

func TestPersist_InsertErrorDoesNotFailPush(t *testing.T) {
	persister := newFakePersister()
	persister.err = errors.New("supabase down")
	meta := &fakeRunMetaFetcher{rows: map[string]*RunMeta{"run-1": {UserID: "user-A"}}}
	base, teardown := newPersistServer(t, &Server{Persister: persister, RunMeta: meta})
	defer teardown()

	// The push must still be 202 — the mirror is best-effort.
	pushOK(t, base, "run-1", `{"lat":1,"lng":2,"distance_m":0,"elapsed_s":0}`)
	// And the insert was still attempted (error swallowed in the goroutine).
	select {
	case got := <-persister.ch:
		if got.userID != "user-A" {
			t.Fatalf("insert userID=%q, want user-A", got.userID)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("insert was not attempted")
	}
}

func TestPersist_SkippedWhenRunRowMissing(t *testing.T) {
	// RunMeta returns nil (run row gone) → nothing to persist, no
	// insert with an empty user_id (which would violate NOT NULL).
	persister := newFakePersister()
	meta := &fakeRunMetaFetcher{rows: map[string]*RunMeta{}} // no row for run-1
	base, teardown := newPersistServer(t, &Server{Persister: persister, RunMeta: meta})
	defer teardown()

	pushOK(t, base, "run-1", `{"lat":1,"lng":2,"distance_m":0,"elapsed_s":0}`)
	select {
	case got := <-persister.ch:
		t.Fatalf("insert attempted with missing run row: %+v", got)
	case <-time.After(300 * time.Millisecond):
		// Expected: no insert.
	}
}

// bpm is Art 9 data: an owner who may not share it has it removed before the
// ping is published or persisted (decisions § 2265).
func TestPush_StripsBPMWhenHeartRateNotShared(t *testing.T) {
	persister := newFakePersister()
	meta := &fakeRunMetaFetcher{rows: map[string]*RunMeta{"run-1": {UserID: "user-A", IsPublic: true}}}
	consent := &fakeHeartRateConsent{shared: map[string]bool{"user-A": false}}
	hub := NewHub()
	base, teardown := newPersistServer(t, &Server{Hub: hub, Persister: persister, RunMeta: meta, HeartRate: consent})
	defer teardown()

	pushOK(t, base, "run-1", `{"lat":51.5,"lng":-0.1,"distance_m":500,"elapsed_s":120,"bpm":150}`)

	if last := hub.LastKnown("run-1"); last == nil || last.BPM != nil {
		t.Fatalf("published ping must carry no bpm, got %+v", last)
	}
	select {
	case got := <-persister.ch:
		if got.ping.BPM != nil {
			t.Fatalf("persisted ping must carry no bpm, got %+v", got.ping)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("push did not trigger a persist within the deadline")
	}
}

func TestPush_StripsBPMWithoutARunMetaFetcher(t *testing.T) {
	hub := NewHub()
	base, teardown := newPersistServer(t, &Server{Hub: hub})
	defer teardown()
	pushOK(t, base, "run-1", `{"lat":1,"lng":2,"distance_m":0,"elapsed_s":0,"bpm":140}`)
	if last := hub.LastKnown("run-1"); last == nil || last.BPM != nil {
		t.Fatalf("unknown consent must withhold bpm, got %+v", last)
	}
}

type fakeHeartRateConsent struct {
	mu     sync.Mutex
	shared map[string]bool
	err    error
	calls  int
}

func (f *fakeHeartRateConsent) HeartRateShared(_ context.Context, userID string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	if f.err != nil {
		return false, f.err
	}
	return f.shared[userID], nil
}

func (f *fakeHeartRateConsent) set(userID string, shared bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.shared[userID] = shared
}

func (f *fakeHeartRateConsent) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

// Withdrawing health-data consent (or the overlay heart-rate opt-in) must
// stop bpm reaching hub spectators within HeartRateTTL, not within the room
// meta's minute-long CacheRefreshTTL, which this test leaves untouched.
func TestPush_ConsentWithdrawalStopsBPMWithinHeartRateTTL(t *testing.T) {
	t.Cleanup(SetHeartRateTTL(20 * time.Millisecond))
	meta := &fakeRunMetaFetcher{rows: map[string]*RunMeta{"run-1": {UserID: "user-A", IsPublic: true}}}
	consent := &fakeHeartRateConsent{shared: map[string]bool{"user-A": true}}
	hub := NewHub()
	base, teardown := newPersistServer(t, &Server{Hub: hub, RunMeta: meta, HeartRate: consent})
	defer teardown()

	ping := `{"lat":1,"lng":2,"distance_m":0,"elapsed_s":0,"bpm":140}`
	pushOK(t, base, "run-1", ping)
	if last := hub.LastKnown("run-1"); last == nil || last.BPM == nil || *last.BPM != 140 {
		t.Fatalf("a consenting owner's bpm must be published, got %+v", last)
	}

	consent.set("user-A", false)
	time.Sleep(40 * time.Millisecond)
	pushOK(t, base, "run-1", ping)
	if last := hub.LastKnown("run-1"); last == nil || last.BPM != nil {
		t.Fatalf("bpm must stop once consent is withdrawn and HeartRateTTL passes, got %+v", last)
	}
	if meta.calls != 1 {
		t.Fatalf("the room meta must still come from its cache, fetched %d times", meta.calls)
	}
}

func TestPush_HeartRateConsentIsReusedWithinHeartRateTTL(t *testing.T) {
	t.Cleanup(SetHeartRateTTL(time.Hour))
	meta := &fakeRunMetaFetcher{rows: map[string]*RunMeta{"run-1": {UserID: "user-A", IsPublic: true}}}
	consent := &fakeHeartRateConsent{shared: map[string]bool{"user-A": true}}
	base, teardown := newPersistServer(t, &Server{RunMeta: meta, HeartRate: consent})
	defer teardown()
	for i := 0; i < 3; i++ {
		pushOK(t, base, "run-1", `{"lat":1,"lng":2,"distance_m":0,"elapsed_s":0,"bpm":140}`)
	}
	if n := consent.callCount(); n != 1 {
		t.Fatalf("consent fetched %d times within one HeartRateTTL, want 1", n)
	}
}

// A failed consent lookup withholds bpm, is not cached, and never denies the
// ping: heart rate is auxiliary to the location feed.
func TestPush_HeartRateLookupFailureWithholdsBPMOnly(t *testing.T) {
	t.Cleanup(SetHeartRateTTL(time.Hour))
	meta := &fakeRunMetaFetcher{rows: map[string]*RunMeta{"run-1": {UserID: "user-A", IsPublic: true}}}
	consent := &fakeHeartRateConsent{shared: map[string]bool{"user-A": true}, err: errors.New("supabase down")}
	hub := NewHub()
	base, teardown := newPersistServer(t, &Server{Hub: hub, RunMeta: meta, HeartRate: consent})
	defer teardown()

	ping := `{"lat":1,"lng":2,"distance_m":0,"elapsed_s":0,"bpm":140}`
	pushOK(t, base, "run-1", ping)
	if last := hub.LastKnown("run-1"); last == nil || last.BPM != nil {
		t.Fatalf("a failed consent lookup must withhold bpm, got %+v", last)
	}

	consent.mu.Lock()
	consent.err = nil
	consent.mu.Unlock()
	pushOK(t, base, "run-1", ping)
	if last := hub.LastKnown("run-1"); last == nil || last.BPM == nil {
		t.Fatalf("a failure must not be cached as a refusal, got %+v", last)
	}
}
