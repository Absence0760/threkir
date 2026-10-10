package internal

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"
)

type distanceUpdate struct {
	RunID     string
	DistanceM float64
	Bests     map[string]*int
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
	uploadErr   error
	sidecars    map[string]*SmoothedSidecar
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

func (f *fakeBackend) DownloadRecordedTrack(_ context.Context, path string) (*RecordedTrack, error) {
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
	raw, err := json.Marshal(pts)
	if err != nil {
		return nil, err
	}
	return &RecordedTrack{Points: pts, Fingerprint: fingerprintTrack(raw, len(pts))}, nil
}

func (f *fakeBackend) UploadSmoothedSidecar(_ context.Context, path string, sc *SmoothedSidecar) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.distance == nil {
		return errors.New("fake: distance state not configured")
	}
	if f.distance.uploadErr != nil {
		return f.distance.uploadErr
	}
	if f.distance.sidecars == nil {
		f.distance.sidecars = map[string]*SmoothedSidecar{}
	}
	f.distance.sidecars[path] = sc
	return nil
}

func (f *fakeBackend) UpdateRunDistance(_ context.Context, read *DistanceRecomputeRun, upd RunDistanceUpdate) error {
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
	if err := json.Unmarshal(upd.Metadata, &meta); err != nil {
		return err
	}
	f.distance.updates = append(f.distance.updates, distanceUpdate{RunID: read.ID, DistanceM: upd.DistanceM, Bests: upd.EmbeddedBests, Metadata: meta})
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
	// A forward-pass recompute removes a stale sidecar through the Storage
	// fake, which writes into this map.
	b.storageObjects = map[string][]StorageObject{}
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
	if u.Metadata["distance_estimator"] != "kalman_v3" {
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
	if got := b.distance.updates[0].Metadata["distance_estimator"]; got != "kalman_v3" {
		t.Errorf("distance_estimator = %v, want a kalman_v1 recompute restamped kalman_v3", got)
	}
}

// legacyStopTrack is a track recorded before spec v1 (no Doppler keys):
// 60 s north at 3 m/s, 90 s standing still, 60 s more at 3 m/s — 360 m —
// with deterministic +-2 m jitter on every fix.
func legacyStopTrack() []RecordedTrackPoint {
	t0 := time.Date(2026, 10, 8, 7, 0, 0, 0, time.UTC)
	pts := make([]RecordedTrackPoint, 0, 211)
	north := 0.0
	for i := 0; i <= 210; i++ {
		if i > 0 && (i <= 60 || i > 150) {
			north += 3
		}
		lat := 40.0 + (north+2*math.Sin(float64(i)*1.7))/111195.0
		lng := -75.0 + 2*math.Cos(float64(i)*2.3)/(111195.0*math.Cos(40*math.Pi/180))
		ts := t0.Add(time.Duration(i) * time.Second)
		pts = append(pts, RecordedTrackPoint{Lat: &lat, Lng: &lng, Timestamp: &ts, AccuracyM: f64(4)})
	}
	return pts
}

func TestDistanceRecompute_LegacyTrackCreditsNothingThroughTheStop(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), legacyStopTrack())
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	// The hop-sum reads ~784 m; the smoother 357.36 m, and its forward pass,
	// kept here because no road matcher classifies the run, 357.79 m: both
	// carry the post-hoc stop hints.
	if got := b.distance.updates[0].DistanceM; got < 350 || got > 365 {
		t.Errorf("distance_m = %v, want ~360 m (the 90 s stop credits nothing)", got)
	}
}

func TestDistanceRecompute_DopplerTrackKeepsTheSmoothedPass(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), straightDopplerTrack(101, 2.5))
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if got := b.distance.updates[0].Metadata["distance_estimator_pass"]; got != "smoothed" {
		t.Errorf("distance_estimator_pass = %v, want smoothed for a track with Doppler", got)
	}
}

// errRoadMatcher is a RoadDistanceMatcher whose engine answers status.
type errRoadMatcher struct{ status int }

func (errRoadMatcher) Algorithm() string { return "err-road" }
func (errRoadMatcher) Version() string   { return "v1" }
func (m errRoadMatcher) Match(context.Context, []TrackPoint) ([]TrackPoint, error) {
	return nil, &HTTPError{StatusCode: m.status}
}
func (m errRoadMatcher) MatchWithRoadDistance(context.Context, []TrackPoint) ([]TrackPoint, RoadMatch, error) {
	return nil, RoadMatch{}, &HTTPError{StatusCode: m.status}
}

// An engine outage must not decide the pass: a run written now is stamped
// kalman_v3 and never offered Recalculate again, so a road run recomputed
// during a 502 would keep the forward figure for good. The job is deferred
// instead, and nothing is written.
func TestDistanceRecompute_TransientRoadMatchFailureDefersTheJob(t *testing.T) {
	for _, status := range []int{http.StatusBadGateway, http.StatusServiceUnavailable, http.StatusTooManyRequests} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			w, b := distanceWorker(t, appRun(`{}`), legacyStopTrack())
			w.Matcher = errRoadMatcher{status: status}
			err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID}))
			if err == nil {
				t.Fatal("handle returned nil; want the matcher's error so the job is deferred")
			}
			if !isTransient(err) {
				t.Errorf("err %v is not transient; the worker would fail the job instead of deferring it", err)
			}
			if len(b.distance.updates) != 0 {
				t.Errorf("updates = %d, want 0 — nothing may be stamped before the run is classified", len(b.distance.updates))
			}
		})
	}
}

// legacyRoadMatch reports the legacy stop track as matched end to end at the
// smoother's own length, so roadDistanceFor accepts it unless another of its
// checks rules the run out.
func legacyRoadMatch() RoadMatch {
	pts := coordinatePoints(legacyStopTrack())
	return roadOf(replayRecordedTrack(pts, 10).SmoothedM, 0.9)
}

func TestDistanceRecompute_PositionOnlyTrackPicksItsPassByTheRoadClassifier(t *testing.T) {
	pts := coordinatePoints(legacyStopTrack())
	replay := replayRecordedTrack(pts, 10)
	if !replay.PositionOnly || replay.ForwardM == replay.SmoothedM {
		t.Fatalf("fixture must be position-only with distinct passes: positionOnly=%v forward=%v smoothed=%v",
			replay.PositionOnly, replay.ForwardM, replay.SmoothedM)
	}
	forward := math.Round(replay.ForwardM*100) / 100
	smoothed := math.Round(replay.SmoothedM*100) / 100
	cases := []struct {
		name     string
		matcher  Matcher
		mutate   func(*DistanceRecomputeRun)
		wantPass string
		wantM    float64
	}{
		{"no matcher configured", nil, nil, "forward", forward},
		{"matcher without road distance", nopMatcherForRecompute{}, nil, "forward", forward},
		{"matcher refuses the track", errRoadMatcher{status: http.StatusBadRequest}, nil, "forward", forward},
		{"not matched end to end", fakeRoadMatcher{road: RoadMatch{}}, nil, "forward", forward},
		{"matched road run", fakeRoadMatcher{road: legacyRoadMatch()}, nil, "smoothed", smoothed},
		{"matched but a hike", fakeRoadMatcher{road: legacyRoadMatch()},
			func(r *DistanceRecomputeRun) { r.ActivityType = "hike" }, "forward", forward},
		{"matched but on a trail route", fakeRoadMatcher{road: legacyRoadMatch()},
			func(r *DistanceRecomputeRun) { r.Route = &RoadRouteSurface{Surface: strp("trail")} }, "forward", forward},
		{"matched but sub_sport trail", fakeRoadMatcher{road: legacyRoadMatch()},
			func(r *DistanceRecomputeRun) { r.Metadata = json.RawMessage(`{"sub_sport":"trail"}`) }, "forward", forward},
		{"already road-matched by map_match", nil,
			func(r *DistanceRecomputeRun) { r.Metadata = json.RawMessage(`{"distance_map_matched_m":361.2}`) }, "smoothed", smoothed},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			run := appRun(`{}`)
			if tc.mutate != nil {
				tc.mutate(&run)
			}
			w, b := distanceWorker(t, run, legacyStopTrack())
			w.Matcher = tc.matcher
			if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
				t.Fatalf("handle: %v", err)
			}
			u := b.distance.updates[0]
			if got := u.Metadata["distance_estimator_pass"]; got != tc.wantPass {
				t.Errorf("distance_estimator_pass = %v, want %s", got, tc.wantPass)
			}
			if u.DistanceM != tc.wantM {
				t.Errorf("distance_m = %v, want %v (the %s pass)", u.DistanceM, tc.wantM, tc.wantPass)
			}
		})
	}
}

func TestDistanceRecompute_ForwardPassAlsoMeasuresTheBests(t *testing.T) {
	track := zigZagTrack(1800, 6000, 2)
	pts := coordinatePoints(track)
	want := embeddedBestsOver(pts, replayRecordedTrack(pts, 10).ForwardCumM)
	if want["fastest_5k_s"] == nil {
		t.Fatal("fixture must cover 5 km on the forward pass")
	}
	w, b := distanceWorker(t, appRun(`{}`), track)
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	u := b.distance.updates[0]
	if u.Metadata["distance_estimator_pass"] != "forward" {
		t.Fatalf("pass = %v, want forward for a position-only run nothing classifies as road", u.Metadata["distance_estimator_pass"])
	}
	for col, wv := range want {
		have := u.Bests[col]
		if (wv == nil) != (have == nil) || (wv != nil && *wv != *have) {
			t.Errorf("%s = %v, want the forward cumulative's %v", col, have, wv)
		}
	}
}

// nopMatcherForRecompute is a Matcher that cannot measure road distance.
type nopMatcherForRecompute struct{}

func (nopMatcherForRecompute) Algorithm() string { return "nop" }
func (nopMatcherForRecompute) Version() string   { return "v1" }
func (nopMatcherForRecompute) Match(_ context.Context, pts []TrackPoint) ([]TrackPoint, error) {
	return pts, nil
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
		{"saved by the smoother on the phone", func(r *DistanceRecomputeRun) {
			r.Metadata = json.RawMessage(`{"distance_estimator":"kalman_v3"}`)
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
	pts := coordinatePoints(track)
	replay := replayRecordedTrack(pts, 10)
	cum, fixes := replay.SmoothedCumM, replay.Fixes
	if len(pts) != 11 || fixes != 10 || cum[0] != 0 || cum[1] != 0 || cum[2] != 2.5 {
		t.Errorf("points = %d, fixes = %d, cum[:3] = %v", len(pts), fixes, cum[:3])
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
	if !strings.Contains(query, "select=id%2Cuser_id%2Csource%2Cactivity_type%2Ctrack_url%2Cdistance_m%2Cmetadata%2Croute%3Aroutes%28surface%29") {
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
	track, err := client.DownloadRecordedTrack(context.Background(), drTrack)
	if err != nil {
		t.Fatalf("download: %v", err)
	}
	pts := track.Points
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
	fiveK := 1498
	if err := client.UpdateRunDistance(context.Background(), &run, RunDistanceUpdate{
		DistanceM:     5000.12,
		EmbeddedBests: map[string]*int{"fastest_5k_s": &fiveK, "fastest_10k_s": nil},
		Metadata:      json.RawMessage(`{"title":"a, b","distance_estimator":"kalman_v2"}`),
	}); err != nil {
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
	if string(gotBody["distance_m"]) != "5000.12" || !strings.Contains(string(gotBody["metadata"]), "kalman_v2") {
		t.Errorf("body = %v", gotBody)
	}
	if string(gotBody["fastest_5k_s"]) != "1498" || string(gotBody["fastest_10k_s"]) != "null" {
		t.Errorf("bests in body = %s / %s, want 1498 / null", gotBody["fastest_5k_s"], gotBody["fastest_10k_s"])
	}

	respond = `[]`
	if err := client.UpdateRunDistance(context.Background(), &run, RunDistanceUpdate{DistanceM: 1, Metadata: json.RawMessage(`{}`)}); !errors.Is(err, ErrRunChangedDuringRecompute) {
		t.Errorf("zero-row PATCH: err = %v, want ErrRunChangedDuringRecompute", err)
	}

	respond = `[{"id":"x"}]`
	nullRun := appRun(`null`)
	if err := client.UpdateRunDistance(context.Background(), &nullRun, RunDistanceUpdate{DistanceM: 1, Metadata: json.RawMessage(`{}`)}); err != nil {
		t.Fatalf("update: %v", err)
	}
	if gotQuery.Get("metadata") != "is.null" {
		t.Errorf("null metadata filter = %q, want is.null", gotQuery.Get("metadata"))
	}
}

func TestDistanceRecompute_WritesEmbeddedBestsFromTheEstimatorCumulative(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), zigZagTrack(1800, 6000, 2))
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	u := b.distance.updates[0]
	if len(u.Bests) != 4 {
		t.Fatalf("bests = %v, want all four columns", u.Bests)
	}
	if s := u.Bests["fastest_5k_s"]; s == nil || *s < 1480 || *s > 1520 {
		t.Errorf("fastest_5k_s = %v, want ~1500 s (6 km at 5:00/km)", s)
	}
	for _, col := range []string{"fastest_10k_s", "fastest_half_marathon_s", "fastest_marathon_s"} {
		if u.Bests[col] != nil {
			t.Errorf("%s = %d, want null for a 6 km run", col, *u.Bests[col])
		}
	}
}

func TestDistanceRecompute_ShortRunNullsEveryEmbeddedBest(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), straightDopplerTrack(101, 2.5))
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	bests := b.distance.updates[0].Bests
	for _, d := range embeddedBestDistances {
		v, ok := bests[d.Column]
		if !ok || v != nil {
			t.Errorf("%s: present = %v, value = %v; want an explicit null", d.Column, ok, v)
		}
	}
}

const smoothedTrackJSON = `[{"lat":40,"lng":-75,"ts":"2026-10-08T07:00:00Z","smoothedLat":40.00001,"smoothedLng":-75.00002},` +
	`{"lat":40.0001,"lng":-75,"ts":"2026-10-08T07:00:01Z","smoothedLat":40.00009},` +
	`{"lat":40.0002,"lng":-75,"ts":"2026-10-08T07:00:02Z"}]`

func TestDownloadRecordedTrack_FeedsTheSmootherRawPositions(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(smoothedTrackJSON))
	})
	track, err := client.DownloadRecordedTrack(context.Background(), drTrack)
	if err != nil {
		t.Fatalf("download: %v", err)
	}
	pts := track.Points
	if *pts[0].Lat != 40 || *pts[0].Lng != -75 {
		t.Errorf("pts[0] = (%v, %v); the recompute must replay the raw fix, not a previous smoothing", *pts[0].Lat, *pts[0].Lng)
	}
}

func TestParseTrack_PrefersTheSmoothedPairOnlyWhenBothArePresent(t *testing.T) {
	pts, err := parseTrack([]byte(smoothedTrackJSON))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	want := [][2]float64{{40.00001, -75.00002}, {40.0001, -75}, {40.0002, -75}}
	for i, w := range want {
		if pts[i].Lat != w[0] || pts[i].Lng != w[1] {
			t.Errorf("pts[%d] = (%v, %v), want (%v, %v)", i, pts[i].Lat, pts[i].Lng, w[0], w[1])
		}
	}
	out, _ := json.Marshal(pts)
	if strings.Contains(string(out), "smoothed") {
		t.Errorf("a matcher point re-encodes the smoothed keys: %s", out)
	}
}
