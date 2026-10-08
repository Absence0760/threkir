package internal

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

type fakeRoadDistance struct {
	runs map[string]*RoadDistanceRun
	// casMisses UpdateRunMetadata calls answer ErrRunMetadataChanged
	// before one is applied.
	casMisses int
	writes    []map[string]any
}

func (f *fakeBackend) ReadRunForRoadDistance(_ context.Context, runID string) (*RoadDistanceRun, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.road == nil {
		return nil, ErrRunNotFound
	}
	run, ok := f.road.runs[runID]
	if !ok {
		return nil, ErrRunNotFound
	}
	cp := *run
	return &cp, nil
}

func (f *fakeBackend) UpdateRunMetadata(_ context.Context, read *RoadDistanceRun, trackURL string, metadata json.RawMessage) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.road.casMisses > 0 {
		f.road.casMisses--
		return ErrRunMetadataChanged
	}
	stored := f.road.runs[read.ID]
	if stored.TrackURL == nil || *stored.TrackURL != trackURL {
		return ErrRunMetadataChanged
	}
	var meta map[string]any
	if err := json.Unmarshal(metadata, &meta); err != nil {
		return err
	}
	f.road.writes = append(f.road.writes, meta)
	stored.Metadata = metadata
	return nil
}

func strp(s string) *string { return &s }

// roadTrack is n points heading due north 10 m apart: a 2 km footprint for
// n = 201.
func roadTrack(n int) []TrackPoint {
	pts := make([]TrackPoint, n)
	for i := range pts {
		pts[i] = TrackPoint{Lat: 51.5 + float64(i)*10/111195.0, Lng: -0.1}
	}
	return pts
}

func roadRun(meta string) *RoadDistanceRun {
	return &RoadDistanceRun{
		ID: "run-1", ActivityType: strp("run"), TrackURL: strp("user-1/run-1.json.gz"),
		DistanceM: 2000, Metadata: json.RawMessage(meta),
	}
}

func roadOf(m float64, conf float64) RoadMatch { return RoadMatch{DistanceM: &m, MinConfidence: conf} }

func TestRoadDistanceFor_StoresAnEligibleRoadRun(t *testing.T) {
	got, reason := roadDistanceFor(roadRun(`{}`), map[string]json.RawMessage{}, roadTrack(201), roadOf(1987.46, 0.9))
	if got == nil || *got != 1987.5 {
		t.Fatalf("got %v (%s), want 1987.5", got, reason)
	}
}

func TestRoadDistanceFor_NeverTrailsTracksOrIndoor(t *testing.T) {
	surface := func(s string) *RoadDistanceRun {
		r := roadRun(`{}`)
		r.Route = &RoadRouteSurface{Surface: strp(s)}
		return r
	}
	hike := roadRun(`{}`)
	hike.ActivityType = strp("hike")
	cycle := roadRun(`{}`)
	cycle.ActivityType = strp("cycle")
	noDistance := roadRun(`{}`)
	noDistance.DistanceM = 0
	good := roadOf(2000, 0.9)
	cases := []struct {
		name string
		run  *RoadDistanceRun
		meta string
		raw  []TrackPoint
		road RoadMatch
	}{
		{"hike", hike, `{}`, roadTrack(201), good},
		{"cycle", cycle, `{}`, roadTrack(201), good},
		{"indoor", roadRun(`{}`), `{"indoor":true}`, roadTrack(201), good},
		{"fit trail", roadRun(`{}`), `{"sub_sport":"trail"}`, roadTrack(201), good},
		{"fit track", roadRun(`{}`), `{"sub_sport":"track"}`, roadTrack(201), good},
		{"strava trail run", roadRun(`{}`), `{"strava_activity_type":"TrailRun"}`, roadTrack(201), good},
		{"trail route", surface("trail"), `{}`, roadTrack(201), good},
		{"mixed route", surface("mixed"), `{}`, roadTrack(201), good},
		{"track-sized footprint", roadRun(`{}`), `{}`, roadTrack(20), good},
		{"partly unmatched", roadRun(`{}`), `{}`, roadTrack(201), RoadMatch{}},
		{"low confidence", roadRun(`{}`), `{}`, roadTrack(201), roadOf(2000, 0.3)},
		{"disagrees with distance_m", roadRun(`{}`), `{}`, roadTrack(201), roadOf(2400, 0.9)},
		{"no recorded distance", noDistance, `{}`, roadTrack(201), good},
	}
	for _, c := range cases {
		meta, err := decodeRunMetadata(json.RawMessage(c.meta))
		if err != nil {
			t.Fatal(err)
		}
		if got, reason := roadDistanceFor(c.run, meta, c.raw, c.road); got != nil || reason == "" {
			t.Errorf("%s: got %v reason %q, want no road distance with a reason", c.name, got, reason)
		}
	}
	for _, ok := range []string{`{"sub_sport":"road"}`, `{"sub_sport":"street"}`, `{"strava_activity_type":"Run"}`} {
		meta, _ := decodeRunMetadata(json.RawMessage(ok))
		if got, reason := roadDistanceFor(roadRun(`{}`), meta, roadTrack(201), good); got == nil {
			t.Errorf("%s: refused (%s)", ok, reason)
		}
	}
	if got, reason := roadDistanceFor(surface("road"), map[string]json.RawMessage{}, roadTrack(201), good); got == nil {
		t.Errorf("road route refused (%s)", reason)
	}
}

func TestMergeRoadDistance_SetsClearsAndSkipsNoOps(t *testing.T) {
	meta, _ := decodeRunMetadata(json.RawMessage(`{"title":"x","distance_map_matched_m":1500.2}`))
	v := 1500.2
	if _, changed, _ := mergeRoadDistance(meta, &v); changed {
		t.Error("an unchanged value must not write")
	}
	w := 1600.0
	merged, changed, err := mergeRoadDistance(meta, &w)
	if err != nil || !changed || !strings.Contains(string(merged), `"distance_map_matched_m":1600`) || !strings.Contains(string(merged), `"title":"x"`) {
		t.Errorf("set: %s %v %v", merged, changed, err)
	}
	merged, changed, _ = mergeRoadDistance(meta, nil)
	if !changed || strings.Contains(string(merged), "distance_map_matched_m") {
		t.Errorf("clear: %s %v", merged, changed)
	}
	empty, _ := decodeRunMetadata(json.RawMessage(`{"title":"x"}`))
	if _, changed, _ := mergeRoadDistance(empty, nil); changed {
		t.Error("clearing an absent key must not write")
	}
}

// fakeRoadMatcher is a RoadDistanceMatcher that passes the track through
// and reports a scripted road length.
type fakeRoadMatcher struct{ road RoadMatch }

func (fakeRoadMatcher) Algorithm() string { return "fake-road" }
func (fakeRoadMatcher) Version() string   { return "v1" }
func (m fakeRoadMatcher) Match(ctx context.Context, pts []TrackPoint) ([]TrackPoint, error) {
	out, _, err := m.MatchWithRoadDistance(ctx, pts)
	return out, err
}
func (m fakeRoadMatcher) MatchWithRoadDistance(_ context.Context, pts []TrackPoint) ([]TrackPoint, RoadMatch, error) {
	out := make([]TrackPoint, len(pts))
	copy(out, pts)
	return out, m.road, nil
}

func roadWorker(t *testing.T, run *RoadDistanceRun, road RoadMatch) (*Worker, *fakeBackend, *Job) {
	t.Helper()
	b := newFakeBackend()
	b.trackURL = *run.TrackURL
	b.trackByPath[*run.TrackURL] = roadTrack(201)
	b.road = &fakeRoadDistance{runs: map[string]*RoadDistanceRun{run.ID: run}}
	job := &Job{ID: 1, Kind: "map_match", Payload: mustPayload(t, MapMatchPayload{RunID: run.ID, UserID: "user-1"})}
	return newTestWorker(b, fakeRoadMatcher{road: road}), b, job
}

func TestHandleMapMatch_StoresRoadDistanceBesideTheRecomputeKeys(t *testing.T) {
	run := roadRun(`{"distance_recomputed_at":"2026-10-08T00:00:00Z","distance_recorded_m":2500}`)
	w, b, job := roadWorker(t, run, roadOf(1990, 0.8))
	b.road.casMisses = 1
	if err := w.handleMapMatch(context.Background(), job); err != nil {
		t.Fatal(err)
	}
	if len(b.road.writes) != 1 {
		t.Fatalf("writes=%d, want 1 after one CAS retry", len(b.road.writes))
	}
	got := b.road.writes[0]
	if got[schema.MetaDistanceMapMatchedM] != 1990.0 {
		t.Errorf("distance_map_matched_m=%v", got[schema.MetaDistanceMapMatchedM])
	}
	// The stale-copy guard (20270719000003) restores the recompute keys on a
	// write whose bag lacks distance_recomputed_at; carrying them means this
	// write is never mistaken for one.
	if got["distance_recomputed_at"] != "2026-10-08T00:00:00Z" || got["distance_recorded_m"] != 2500.0 {
		t.Errorf("recompute keys not carried: %v", got)
	}
}

func TestHandleMapMatch_ClearsAStaleRoadDistance(t *testing.T) {
	run := roadRun(`{"distance_map_matched_m":1990,"sub_sport":"trail"}`)
	w, b, job := roadWorker(t, run, roadOf(1990, 0.8))
	if err := w.handleMapMatch(context.Background(), job); err != nil {
		t.Fatal(err)
	}
	if len(b.road.writes) != 1 {
		t.Fatalf("writes=%d, want 1", len(b.road.writes))
	}
	if _, ok := b.road.writes[0][schema.MetaDistanceMapMatchedM]; ok {
		t.Errorf("stale key kept: %v", b.road.writes[0])
	}
}

func TestHandleMapMatch_RoadDistanceNeverFailsTheJob(t *testing.T) {
	run := roadRun(`{}`)
	w, b, job := roadWorker(t, run, roadOf(1990, 0.8))
	b.road.casMisses = roadDistanceMaxAttempts
	if err := w.handleMapMatch(context.Background(), job); err != nil {
		t.Fatalf("job failed on an auxiliary write: %v", err)
	}
	if len(b.road.writes) != 0 || len(b.rowSets) != 1 || b.rowSets[0].Row.Status != "matched" {
		t.Errorf("writes=%v rowSets=%+v", b.road.writes, b.rowSets)
	}
}

func TestHandleMapMatch_PassthroughWritesNoRoadDistance(t *testing.T) {
	run := roadRun(`{}`)
	_, b, job := roadWorker(t, run, RoadMatch{})
	w := newTestWorker(b, PassthroughMatcher{})
	if err := w.handleMapMatch(context.Background(), job); err != nil {
		t.Fatal(err)
	}
	if len(b.road.writes) != 0 {
		t.Errorf("writes=%v, want none", b.road.writes)
	}
}

// osrmRoad renders a /match response snapping every coordinate to itself,
// with the given matchings' distances.
func osrmRoad(coords string, distances ...float64) string {
	var sb strings.Builder
	sb.WriteString(`{"code":"Ok","matchings":[`)
	for i, d := range distances {
		if i > 0 {
			sb.WriteByte(',')
		}
		fmt.Fprintf(&sb, `{"confidence":0.9,"distance":%g}`, d)
	}
	sb.WriteString(`],"tracepoints":[`)
	for i, c := range strings.Split(coords, ";") {
		if i > 0 {
			sb.WriteByte(',')
		}
		fmt.Fprintf(&sb, `{"location":[%s]}`, c)
	}
	sb.WriteString(`]}`)
	return sb.String()
}

func TestOSRMMatcher_RoadDistanceSumsChunksAndTheirJoins(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, osrmRoad(r.URL.Path[len("/match/v1/foot/"):], 1000))
	}))
	defer srv.Close()
	m := NewOSRMMatcher(srv.URL)
	m.ChunkSize = 100
	in := roadTrack(201)
	out, road, err := m.MatchWithRoadDistance(context.Background(), in)
	if err != nil {
		t.Fatal(err)
	}
	if len(out) != 201 || road.DistanceM == nil {
		t.Fatalf("len=%d road=%+v", len(out), road)
	}
	// Two 100-point chunks at 1000 m each, a 10 m hop between them, and a
	// 10 m hop to the one-point tail.
	want := 2000 + haversineM(out[99], out[100]) + haversineM(out[199], out[200])
	if diff := *road.DistanceM - want; diff > 1e-6 || diff < -1e-6 {
		t.Errorf("road=%v want %v", *road.DistanceM, want)
	}
	if road.MinConfidence != 0.9 {
		t.Errorf("confidence=%v", road.MinConfidence)
	}
}

func TestOSRMMatcher_NoRoadDistanceWhenAChunkSplitsOrIsUnmatched(t *testing.T) {
	for name, body := range map[string]func(coords string) string{
		"two matchings": func(c string) string { return osrmRoad(c, 400, 500) },
		"no distance":   func(c string) string { return strings.Replace(osrmRoad(c, 1), `,"distance":1`, ``, 1) },
		"not ok":        func(string) string { return `{"code":"NoMatch"}` },
		"an outlier": func(c string) string {
			return strings.Replace(osrmRoad(c, 900), `{"location":[`+strings.Split(c, ";")[3]+`]}`, `null`, 1)
		},
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprint(w, body(r.URL.Path[len("/match/v1/foot/"):]))
		}))
		m := NewOSRMMatcher(srv.URL)
		out, road, err := m.MatchWithRoadDistance(context.Background(), roadTrack(50))
		srv.Close()
		if err != nil || len(out) != 50 {
			t.Errorf("%s: len=%d err=%v", name, len(out), err)
		}
		if road.DistanceM != nil {
			t.Errorf("%s: road distance %v, want none", name, *road.DistanceM)
		}
	}
}
