package internal

import (
	"context"
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// canopyTrack is the shared canopy_20_50 vector as a watch stores it since
// track_complete: every fix the estimator took, with the 60 s stretch under
// trees (stated 35 m, past the watches' 30 m track gate) flagged offTrack.
// It returns the track and the recorder's smoothed figure for it.
func canopyTrack(t *testing.T) ([]RecordedTrackPoint, float64) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "fixtures", "gps_distance_vectors.json"))
	if err != nil {
		t.Fatal(err)
	}
	var vf struct {
		Scenarios []struct {
			Name   string `json:"name"`
			Events []struct {
				Type     string   `json:"type"`
				T        float64  `json:"t"`
				Lat      *float64 `json:"lat"`
				Lng      *float64 `json:"lng"`
				Acc      *float64 `json:"acc"`
				Speed    *float64 `json:"speed"`
				SpeedAcc *float64 `json:"speedAcc"`
				Bearing  *float64 `json:"bearing"`
			} `json:"events"`
			Smoothed struct {
				DistanceM float64 `json:"distanceM"`
			} `json:"smoothed"`
		} `json:"scenarios"`
	}
	if err := json.Unmarshal(raw, &vf); err != nil {
		t.Fatal(err)
	}
	t0 := time.Date(2026, 10, 15, 7, 0, 0, 0, time.UTC)
	for _, s := range vf.Scenarios {
		if s.Name != "canopy_20_50" {
			continue
		}
		var track []RecordedTrackPoint
		for _, e := range s.Events {
			if e.Type != "fix" || e.Lat == nil || e.Lng == nil {
				continue
			}
			ts := t0.Add(time.Duration(math.Round(e.T*1000)) * time.Millisecond)
			track = append(track, RecordedTrackPoint{
				Lat: e.Lat, Lng: e.Lng, Timestamp: &ts,
				AccuracyM: e.Acc, SpeedMps: e.Speed, SpeedAccuracyMps: e.SpeedAcc, BearingDeg: e.Bearing,
				OffTrack: e.Acc != nil && *e.Acc > 30,
			})
		}
		return track, s.Smoothed.DistanceM
	}
	t.Fatal("canopy_20_50 is gone from the shared vectors")
	return nil, 0
}

func recomputeWatchTrack(t *testing.T, metadata string, track []RecordedTrackPoint) (float64, *fakeBackend) {
	t.Helper()
	run := appRun(metadata)
	run.Source = "watch"
	w, b := distanceWorker(t, run, track)
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if len(b.distance.updates) != 1 {
		t.Fatalf("updates = %d, want the run recomputed", len(b.distance.updates))
	}
	return b.distance.updates[0].DistanceM, b
}

// A watch canopy stretch stored as offTrack fixes replays from its fixes and
// Doppler to the recorder's own smoothed figure; the same track without them,
// which is what the watches stored before track_complete, reads short because
// the replay can credit the stretch only its chord. reference.py
// smooth_distance over the vector minus the 60 fixes past 30 m reads
// 462.549 m against 476.441 m (-2.9%).
func TestDistanceRecompute_ReplaysOffTrackCanopyFixesToTheRecordersFigure(t *testing.T) {
	track, recorder := canopyTrack(t)
	off := 0
	for _, p := range track {
		if p.OffTrack {
			off++
		}
	}
	if off != 60 {
		t.Fatalf("offTrack fixes = %d, want the vector's 60 s canopy stretch", off)
	}
	const meta = `{"distance_estimator":"kalman_v4","track_complete":true}`

	full, b := recomputeWatchTrack(t, meta, track)
	if math.Abs(full-recorder) > 0.006 {
		t.Errorf("recompute with offTrack fixes = %.3f m, recorder's smoothed figure = %.3f m", full, recorder)
	}
	if md := b.distance.updates[0].Metadata; md["distance_estimator_pass"] != EstimatorPassSmoothed {
		t.Errorf("pass = %v, want smoothed (the track carries Doppler)", md["distance_estimator_pass"])
	}

	var gated []RecordedTrackPoint
	for _, p := range track {
		if !p.OffTrack {
			gated = append(gated, p)
		}
	}
	short, _ := recomputeWatchTrack(t, meta, gated)
	if math.Abs(short-462.549) > 0.05 {
		t.Errorf("recompute without the canopy fixes = %.3f m, reference.py reads 462.549 m", short)
	}
	if recorder-short < 10 {
		t.Errorf("dropping the canopy fixes cost %.3f m; the case no longer proves the flag matters", recorder-short)
	}
}

// From spec v1.4 a recorder feeds its estimator fixes its track gate refuses,
// so a live kalman_v4 stamp names a complete track only when the run says
// track_complete. Any other live stamp is judged as before.
func TestDistanceRecompute_LiveV14WatchStampNeedsACompleteTrack(t *testing.T) {
	cases := []struct {
		metadata string
		want     bool
	}{
		{`{"distance_estimator":"kalman_v4"}`, false},
		{`{"distance_estimator":"kalman_v4","track_complete":false}`, false},
		{`{"distance_estimator":"kalman_v4","track_complete":"true"}`, false},
		{`{"distance_estimator":"kalman_v4","track_complete":true}`, true},
		{`{"distance_estimator":"kalman_v1"}`, true},
		{`{"distance_estimator":"kalman_v3"}`, true},
		{`{"distance_estimator":"something_older"}`, true},
		// A recompute stamped it: the stamp no longer names the recorder.
		{`{"distance_estimator":"kalman_v4","distance_recomputed_at":"2026-10-15T10:00:00Z"}`, true},
		{`{}`, true},
	}
	for _, c := range cases {
		run := appRun(c.metadata)
		run.Source = "watch"
		w, b := distanceWorker(t, run, straightDopplerTrack(101, 2.5))
		if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
			t.Fatalf("%s: a skip must complete the job, got %v", c.metadata, err)
		}
		if got := len(b.distance.updates) == 1; got != c.want {
			t.Errorf("%s: recomputed = %v, want %v", c.metadata, got, c.want)
		}
	}
}

func TestSmoothedSidecar_PlacesNoPositionOnAnOffTrackFix(t *testing.T) {
	track, _ := canopyTrack(t)
	_, b := recomputeWatchTrack(t, `{"distance_estimator":"kalman_v4","track_complete":true}`, track)
	sc := b.distance.sidecars[smoothedSidecarPath(drUserID, drRunID)]
	if sc == nil {
		t.Fatal("no sidecar written for a Doppler track")
	}
	if len(sc.Positions) != len(track) {
		t.Fatalf("sidecar positions = %d, want one per stored waypoint (%d)", len(sc.Positions), len(track))
	}
	for i, p := range track {
		if p.OffTrack && sc.Positions[i] != nil {
			t.Errorf("waypoint %d is offTrack but the sidecar places it at %v", i, *sc.Positions[i])
		}
		if !p.OffTrack && sc.Positions[i] == nil {
			t.Errorf("waypoint %d is on the line but the sidecar placed nothing", i)
		}
	}
}

func TestParseTrack_DropsOffTrackFixes(t *testing.T) {
	body := []byte(`[
		{"lat":1,"lng":2,"ts":"2026-10-15T07:00:00Z"},
		{"lat":1.5,"lng":2.5,"ts":"2026-10-15T07:00:01Z","offTrack":true,"smoothedLat":9,"smoothedLng":9},
		{"lat":3,"lng":4,"ts":"2026-10-15T07:00:02Z","offTrack":false}
	]`)
	pts, err := parseTrack(body)
	if err != nil {
		t.Fatal(err)
	}
	if len(pts) != 2 || pts[0].Lat != 1 || pts[1].Lat != 3 {
		t.Fatalf("parseTrack = %+v, want the two on-track fixes", pts)
	}
	out, err := json.Marshal(pts)
	if err != nil {
		t.Fatal(err)
	}
	var back []map[string]any
	if err := json.Unmarshal(out, &back); err != nil {
		t.Fatal(err)
	}
	for _, p := range back {
		if _, ok := p["offTrack"]; ok {
			t.Errorf("a matched or exported point carries offTrack: %v", p)
		}
	}
}

func TestOnTrackRaw_DropsOffTrackFixes(t *testing.T) {
	track, _ := canopyTrack(t)
	raw := onTrackRaw(track)
	if len(raw) != len(track)-60 {
		t.Fatalf("onTrackRaw kept %d of %d fixes, want all but the 60 offTrack ones", len(raw), len(track))
	}
}
