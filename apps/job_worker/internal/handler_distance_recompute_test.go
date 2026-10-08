package internal

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"
)

type distanceUpdate struct {
	RunID     string
	DistanceM float64
	Metadata  map[string]any
}

type fakeDistanceRecompute struct {
	runs   map[string]*DistanceRecomputeRun
	tracks map[string][]RecordedTrackPoint
	// casMisses UpdateRunDistance calls answer ErrRunChangedDuringRecompute
	// before one is applied.
	casMisses   int
	readErr     error
	downloadErr error
	reads       int
	updates     []distanceUpdate
}

func (f *fakeBackend) ReadRunForDistanceRecompute(_ context.Context, runID string) (*DistanceRecomputeRun, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.distance == nil {
		return nil, errors.New("fake: distance state not configured")
	}
	f.distance.reads++
	if f.distance.readErr != nil {
		return nil, f.distance.readErr
	}
	run, ok := f.distance.runs[runID]
	if !ok {
		return nil, ErrRunNotFound
	}
	cp := *run
	return &cp, nil
}

func (f *fakeBackend) DownloadRecordedTrack(_ context.Context, path string) ([]RecordedTrackPoint, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.distance == nil {
		return nil, errors.New("fake: distance state not configured")
	}
	if f.distance.downloadErr != nil {
		return nil, f.distance.downloadErr
	}
	pts, ok := f.distance.tracks[path]
	if !ok {
		return nil, &HTTPError{StatusCode: http.StatusNotFound}
	}
	return pts, nil
}

func (f *fakeBackend) UpdateRunDistance(_ context.Context, read *DistanceRecomputeRun, distanceM float64, metadata json.RawMessage) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.distance == nil {
		return errors.New("fake: distance state not configured")
	}
	if f.distance.casMisses > 0 {
		f.distance.casMisses--
		return ErrRunChangedDuringRecompute
	}
	var meta map[string]any
	if err := json.Unmarshal(metadata, &meta); err != nil {
		return err
	}
	f.distance.updates = append(f.distance.updates, distanceUpdate{RunID: read.ID, DistanceM: distanceM, Metadata: meta})
	return nil
}

const (
	drRunID  = "0b6f1c3e-9a43-4d5e-8f21-6c7d8e9f0a1b"
	drUserID = "5e2d4c1b-7a8f-4b3c-9d6e-1f2a3b4c5d6e"
	drTrack  = drUserID + "/" + drRunID + ".json.gz"
)

func f64(v float64) *float64 { return &v }

// straightDopplerTrack is n fixes 1 s apart heading due north with a
// Doppler speed of speedMps. With usable Doppler every fix after the
// anchor credits exactly speed * dt, so the recomputed distance is
// (n - 1) * speedMps regardless of the positions' noise.
func straightDopplerTrack(n int, speedMps float64) []RecordedTrackPoint {
	t0 := time.Date(2026, 10, 8, 7, 0, 0, 0, time.UTC)
	pts := make([]RecordedTrackPoint, n)
	for i := range pts {
		ts := t0.Add(time.Duration(i) * time.Second)
		lat := 40.0 + float64(i)*speedMps/111195.0
		lng := -75.0
		pts[i] = RecordedTrackPoint{
			Lat: &lat, Lng: &lng, Timestamp: &ts,
			AccuracyM: f64(4), SpeedMps: f64(speedMps), SpeedAccuracyMps: f64(0.4), BearingDeg: f64(0),
		}
	}
	return pts
}

func distanceWorker(t *testing.T, run DistanceRecomputeRun, track []RecordedTrackPoint) (*Worker, *fakeBackend) {
	t.Helper()
	b := newFakeBackend()
	b.distance = &fakeDistanceRecompute{
		runs:   map[string]*DistanceRecomputeRun{run.ID: &run},
		tracks: map[string][]RecordedTrackPoint{},
	}
	if run.TrackURL != nil {
		b.distance.tracks[*run.TrackURL] = track
	}
	return newTestWorker(b, nil), b
}

func appRun(metadata string) DistanceRecomputeRun {
	track := drTrack
	return DistanceRecomputeRun{
		ID: drRunID, UserID: drUserID, Source: "app", ActivityType: "run",
		TrackURL: &track, DistanceM: 6308.7, Metadata: json.RawMessage(metadata),
	}
}

func distanceJob(t *testing.T, p DistanceRecomputePayload) *Job {
	t.Helper()
	raw, err := json.Marshal(p)
	if err != nil {
		t.Fatal(err)
	}
	return &Job{ID: 1, Kind: "distance_recompute", Payload: raw}
}

func TestDistanceRecompute_RewritesDistanceAndKeepsEveryOtherKey(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{"title":"Morning loop","steps":4100}`), straightDopplerTrack(101, 2.5))
	if err := w.dispatch(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID, UserID: drUserID})); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if len(b.distance.updates) != 1 {
		t.Fatalf("updates = %d, want 1", len(b.distance.updates))
	}
	u := b.distance.updates[0]
	if u.DistanceM != 250 {
		t.Errorf("distance_m = %v, want 250 (100 s at a Doppler 2.5 m/s)", u.DistanceM)
	}
	if u.Metadata["title"] != "Morning loop" || u.Metadata["steps"] != float64(4100) {
		t.Errorf("existing keys clobbered: %v", u.Metadata)
	}
	if u.Metadata["distance_recorded_m"] != 6308.7 {
		t.Errorf("distance_recorded_m = %v, want the old distance_m 6308.7", u.Metadata["distance_recorded_m"])
	}
	if u.Metadata["distance_estimator"] != "kalman_v1" {
		t.Errorf("distance_estimator = %v", u.Metadata["distance_estimator"])
	}
	at, _ := u.Metadata["distance_recomputed_at"].(string)
	if _, err := time.Parse(time.RFC3339, at); err != nil {
		t.Errorf("distance_recomputed_at %q is not RFC3339: %v", at, err)
	}
}

func TestDistanceRecompute_RepeatKeepsTheOriginalRecordedDistance(t *testing.T) {
	run := appRun(`{"distance_recorded_m":6308.7,"distance_estimator":"kalman_v1","distance_recomputed_at":"2026-10-08T08:00:00Z"}`)
	run.DistanceM = 250
	w, b := distanceWorker(t, run, straightDopplerTrack(101, 2.5))
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if len(b.distance.updates) != 1 {
		t.Fatalf("updates = %d, want 1 — a recomputed run may be recomputed again", len(b.distance.updates))
	}
	if got := b.distance.updates[0].Metadata["distance_recorded_m"]; got != 6308.7 {
		t.Errorf("distance_recorded_m = %v, want the original 6308.7, not the previous recompute's 250", got)
	}
}

func TestDistanceRecompute_NullMetadataGetsABag(t *testing.T) {
	w, b := distanceWorker(t, appRun(`null`), straightDopplerTrack(11, 3))
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if len(b.distance.updates) != 1 || b.distance.updates[0].Metadata["distance_recorded_m"] != 6308.7 {
		t.Fatalf("updates = %+v", b.distance.updates)
	}
}

func TestDistanceRecompute_SkipsWhatIsNotTheEstimatorsToReplace(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*DistanceRecomputeRun)
	}{
		{"no track", func(r *DistanceRecomputeRun) { r.TrackURL = nil }},
		{"empty track url", func(r *DistanceRecomputeRun) { e := ""; r.TrackURL = &e }},
		{"strava import", func(r *DistanceRecomputeRun) { r.Source = "strava" }},
		{"garmin import", func(r *DistanceRecomputeRun) { r.Source = "garmin" }},
		{"healthkit import", func(r *DistanceRecomputeRun) { r.Source = "healthkit" }},
		{"healthconnect import", func(r *DistanceRecomputeRun) { r.Source = "healthconnect" }},
		{"parkrun result", func(r *DistanceRecomputeRun) { r.Source = "parkrun" }},
		{"race result", func(r *DistanceRecomputeRun) { r.Source = "race" }},
		{"pedometer", func(r *DistanceRecomputeRun) { r.Metadata = json.RawMessage(`{"distance_source":"pedometer"}`) }},
		{"treadmill", func(r *DistanceRecomputeRun) {
			r.Metadata = json.RawMessage(`{"indoor":true,"distance_source":"treadmill","indoor_source":"treadmill"}`)
		}},
		{"indoor flag alone", func(r *DistanceRecomputeRun) { r.Metadata = json.RawMessage(`{"indoor":true}`) }},
		{"indoor_estimated alone", func(r *DistanceRecomputeRun) { r.Metadata = json.RawMessage(`{"indoor_estimated":true}`) }},
		{"in progress", func(r *DistanceRecomputeRun) { r.Metadata = json.RawMessage(`{"in_progress":true}`) }},
		{"manual entry", func(r *DistanceRecomputeRun) { r.Metadata = json.RawMessage(`{"manual_entry":true}`) }},
		{"recorded live by the estimator", func(r *DistanceRecomputeRun) {
			r.Metadata = json.RawMessage(`{"distance_estimator":"kalman_v1"}`)
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			run := appRun(`{}`)
			tc.mutate(&run)
			w, b := distanceWorker(t, run, straightDopplerTrack(20, 2.5))
			if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
				t.Fatalf("a skip must complete the job, got %v", err)
			}
			if len(b.distance.updates) != 0 {
				t.Fatalf("skipped run was rewritten: %+v", b.distance.updates)
			}
		})
	}
}

func TestDistanceRecompute_WatchRunIsRecomputed(t *testing.T) {
	run := appRun(`{}`)
	run.Source = "watch"
	w, b := distanceWorker(t, run, straightDopplerTrack(11, 2.5))
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if len(b.distance.updates) != 1 {
		t.Fatalf("a watch-recorded run is app-recorded; updates = %d", len(b.distance.updates))
	}
}

func TestDistanceRecompute_DeletedRunIsANoOp(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), nil)
	other := "11111111-2222-3333-4444-555555555555"
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: other})); err != nil {
		t.Fatalf("a run deleted after enqueue must not fail the job: %v", err)
	}
	if len(b.distance.updates) != 0 {
		t.Fatal("no update expected")
	}
}

func TestDistanceRecompute_TooFewTimestampedWaypointsFailsPermanently(t *testing.T) {
	track := straightDopplerTrack(5, 2.5)
	for i := 1; i < len(track); i++ {
		track[i].Timestamp = nil
	}
	w, b := distanceWorker(t, appRun(`{}`), track)
	err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID}))
	if err == nil {
		t.Fatal("want an error for a track with one timestamped waypoint")
	}
	if isTransient(err) {
		t.Errorf("an untimed track will never recompute; %v must be permanent", err)
	}
	if len(b.distance.updates) != 0 {
		t.Fatal("no update expected")
	}
}

func TestDistanceRecompute_UntimedWaypointsAreSkippedAndTimeStartsAtTheFirstTimedOne(t *testing.T) {
	track := straightDopplerTrack(12, 2.5)
	track[0].Timestamp = nil // the anchor moves to track[1]
	lat := 41.0
	track[5].Lat = nil
	track[5].Lng = &lat
	w, b := distanceWorker(t, appRun(`{}`), track)
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	// 10 usable fixes after the anchor at track[1], minus the
	// coordinate-less track[5]: track[6] then credits a 2 s hop.
	if got := b.distance.updates[0].DistanceM; got != 25 {
		t.Errorf("distance_m = %v, want 25", got)
	}
	fixes := recordedTrackFixes(track)
	if len(fixes) != 10 || fixes[0].T != 0 || fixes[1].T != 1 {
		t.Errorf("fixes = %d, first t = %v, %v", len(fixes), fixes[0].T, fixes[1].T)
	}
}

func TestDistanceRecompute_ReReadsWhenTheRunChangesUnderIt(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), straightDopplerTrack(11, 2.5))
	b.distance.casMisses = 1
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if b.distance.reads != 2 || len(b.distance.updates) != 1 {
		t.Errorf("reads = %d, updates = %d; want a re-read and one applied write", b.distance.reads, len(b.distance.updates))
	}
}

func TestDistanceRecompute_GivesUpWhenTheRunKeepsChanging(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), straightDopplerTrack(11, 2.5))
	b.distance.casMisses = distanceRecomputeMaxAttempts
	err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID}))
	if err == nil {
		t.Fatal("want an error after the attempts are spent")
	}
	if b.distance.reads != distanceRecomputeMaxAttempts {
		t.Errorf("reads = %d, want %d", b.distance.reads, distanceRecomputeMaxAttempts)
	}
}

func TestDistanceRecompute_RejectsBadPayloads(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), straightDopplerTrack(11, 2.5))
	for name, p := range map[string]DistanceRecomputePayload{
		"missing run id": {},
		"not a uuid":     {RunID: "1 or 1=1"},
		"wrong owner":    {RunID: drRunID, UserID: "99999999-9999-9999-9999-999999999999"},
	} {
		if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, p)); err == nil || isTransient(err) {
			t.Errorf("%s: err = %v, want a permanent error", name, err)
		}
	}
	if len(b.distance.updates) != 0 {
		t.Fatal("no update expected")
	}
}

func TestDistanceRecompute_TransientReadFailureIsRetried(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), straightDopplerTrack(11, 2.5))
	b.distance.readErr = &HTTPError{StatusCode: http.StatusServiceUnavailable}
	err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID}))
	if err == nil || !isTransient(err) {
		t.Fatalf("err = %v, want transient", err)
	}
}

func TestMaxSpeedMpsForActivityMirrorsTheDartVocabulary(t *testing.T) {
	want := map[string]float64{"run": 10, "walk": 5, "cycle": 25, "hike": 6, "stroller": 9, "": 10, "unknown": 10}
	for k, v := range want {
		if got := maxSpeedMpsForActivity(k); got != v {
			t.Errorf("maxSpeedMpsForActivity(%q) = %v, want %v", k, got, v)
		}
	}
}

// ─────────────────── Supabase wire shape ───────────────────

func TestReadRunForDistanceRecompute_NoRowIsErrRunNotFound(t *testing.T) {
	var query string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		query = r.URL.RawQuery
		_, _ = w.Write([]byte(`[]`))
	})
	_, err := client.ReadRunForDistanceRecompute(context.Background(), drRunID)
	if !errors.Is(err, ErrRunNotFound) {
		t.Fatalf("err = %v, want ErrRunNotFound", err)
	}
	if !strings.Contains(query, "select=id%2Cuser_id%2Csource%2Cactivity_type%2Ctrack_url%2Cdistance_m%2Cmetadata") {
		t.Errorf("query = %s", query)
	}
}

func TestDownloadRecordedTrack_DecodesTheDopplerKeys(t *testing.T) {
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	_, _ = zw.Write([]byte(`[{"lat":40,"lng":-75,"ele":12,"ts":"2026-10-08T07:00:00.250Z","accuracyMetres":4.2,"speedMps":2.7,"speedAccuracyMps":0.3,"bearingDeg":91.5},{"lat":40.0001,"lng":-75,"ts":"2026-10-08T07:00:01Z"}]`))
	_ = zw.Close()
	var path string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		path = r.URL.Path
		_, _ = w.Write(buf.Bytes())
	})
	pts, err := client.DownloadRecordedTrack(context.Background(), drTrack)
	if err != nil {
		t.Fatalf("download: %v", err)
	}
	if path != "/storage/v1/object/runs/"+drTrack {
		t.Errorf("path = %s", path)
	}
	if len(pts) != 2 || *pts[0].AccuracyM != 4.2 || *pts[0].SpeedMps != 2.7 || *pts[0].SpeedAccuracyMps != 0.3 || *pts[0].BearingDeg != 91.5 {
		t.Fatalf("pts[0] = %+v", pts[0])
	}
	if pts[1].SpeedMps != nil || pts[1].AccuracyM != nil {
		t.Errorf("a pre-v1 waypoint must leave the Doppler keys nil: %+v", pts[1])
	}
}

func TestUpdateRunDistance_IsConditionalOnTrackAndMetadata(t *testing.T) {
	var gotQuery url.Values
	var gotPrefer string
	var gotBody map[string]json.RawMessage
	respond := `[{"id":"` + drRunID + `"}]`
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPatch {
			t.Errorf("method = %s", r.Method)
		}
		gotQuery = r.URL.Query()
		gotPrefer = r.Header.Get("Prefer")
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, &gotBody)
		_, _ = w.Write([]byte(respond))
	})
	run := appRun(`{"title":"a, b"}`)
	if err := client.UpdateRunDistance(context.Background(), &run, 5000.12, json.RawMessage(`{"title":"a, b","distance_estimator":"kalman_v1"}`)); err != nil {
		t.Fatalf("update: %v", err)
	}
	if gotQuery.Get("id") != "eq."+drRunID || gotQuery.Get("track_url") != "eq."+drTrack {
		t.Errorf("query = %v", gotQuery)
	}
	if gotQuery.Get("metadata") != `eq.{"title":"a, b"}` {
		t.Errorf("metadata filter = %q, want the bag as read", gotQuery.Get("metadata"))
	}
	if gotPrefer != "return=representation" {
		t.Errorf("Prefer = %q — the CAS cannot count rows under return=minimal", gotPrefer)
	}
	if string(gotBody["distance_m"]) != "5000.12" || !strings.Contains(string(gotBody["metadata"]), "kalman_v1") {
		t.Errorf("body = %v", gotBody)
	}

	respond = `[]`
	if err := client.UpdateRunDistance(context.Background(), &run, 1, json.RawMessage(`{}`)); !errors.Is(err, ErrRunChangedDuringRecompute) {
		t.Errorf("zero-row PATCH: err = %v, want ErrRunChangedDuringRecompute", err)
	}

	respond = `[{"id":"x"}]`
	nullRun := appRun(`null`)
	if err := client.UpdateRunDistance(context.Background(), &nullRun, 1, json.RawMessage(`{}`)); err != nil {
		t.Fatalf("update: %v", err)
	}
	if gotQuery.Get("metadata") != "is.null" {
		t.Errorf("null metadata filter = %q, want is.null", gotQuery.Get("metadata"))
	}
}
