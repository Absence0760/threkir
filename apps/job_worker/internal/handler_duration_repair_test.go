package internal

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

type fakeDurationRepair struct {
	runs map[string]*DurationRepairRun
	// casMisses UpdateRunDuration calls answer ErrRunChangedDuringDurationRepair
	// before one is applied.
	casMisses int
	updates   map[string]int
}

func (f *fakeBackend) ReadRunForDurationRepair(_ context.Context, runID string) (*DurationRepairRun, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.durationRepair == nil {
		return nil, errors.New("fake: duration repair state not configured")
	}
	run, ok := f.durationRepair.runs[runID]
	if !ok {
		return nil, ErrRunNotFound
	}
	cp := *run
	return &cp, nil
}

func (f *fakeBackend) UpdateRunDuration(_ context.Context, read *DurationRepairRun, durationS int) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.durationRepair == nil {
		return errors.New("fake: duration repair state not configured")
	}
	if f.durationRepair.casMisses > 0 {
		f.durationRepair.casMisses--
		return ErrRunChangedDuringDurationRepair
	}
	if f.durationRepair.updates == nil {
		f.durationRepair.updates = map[string]int{}
	}
	f.durationRepair.updates[read.ID] = durationS
	return nil
}

const flaggedMeta = `{"duration_repaired": true, "duration_s_original": 44400094}`

// timedTrack is n fixes stepS seconds apart, moving speedMps due north.
func timedTrack(n int, stepS, speedMps float64) []RecordedTrackPoint {
	t0 := time.Date(2026, 11, 5, 7, 0, 0, 0, time.UTC)
	pts := make([]RecordedTrackPoint, n)
	for i := range pts {
		ts := t0.Add(time.Duration(float64(i) * stepS * float64(time.Second)))
		lat := 40.0 + float64(i)*stepS*speedMps/111195.0
		lng := -75.0
		pts[i] = RecordedTrackPoint{Lat: &lat, Lng: &lng, Timestamp: &ts}
	}
	return pts
}

func durationRepairWorker(run DurationRepairRun, track []RecordedTrackPoint) (*Worker, *fakeBackend) {
	b := &fakeBackend{
		durationRepair: &fakeDurationRepair{runs: map[string]*DurationRepairRun{run.ID: &run}},
		distance:       &fakeDistanceRecompute{tracks: map[string][]RecordedTrackPoint{}},
	}
	if track != nil {
		b.distance.tracks[drTrack] = track
	}
	return newTestWorker(b, nil), b
}

func cappedRun() DurationRepairRun {
	track := drTrack
	return DurationRepairRun{
		ID: drRunID, UserID: drUserID, ActivityType: "run", TrackURL: &track,
		DistanceM: 5000, DurationS: MaxRunDurationS, Metadata: json.RawMessage(flaggedMeta),
	}
}

func durationRepairJob(t *testing.T, runID string) *Job {
	t.Helper()
	raw, err := json.Marshal(DurationRepairPayload{RunID: runID, UserID: drUserID})
	if err != nil {
		t.Fatal(err)
	}
	return &Job{ID: 77, Kind: "duration_repair", Payload: raw, Attempts: 1}
}

func TestDurationRepair_WritesTheTrackSpan(t *testing.T) {
	// 5 km over 1501 fixes 2 s apart: a 3000 s (50:00) run.
	w, b := durationRepairWorker(cappedRun(), timedTrack(1501, 2, 5000.0/3000.0))
	if err := w.dispatch(context.Background(), durationRepairJob(t, drRunID)); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if got := b.durationRepair.updates[drRunID]; got != 3000 {
		t.Fatalf("duration written = %d, want 3000", got)
	}
}

func TestDurationRepair_SpanIsEarliestToLatestWhateverTheOrder(t *testing.T) {
	pts := timedTrack(601, 5, 5000.0/3000.0)
	pts[0], pts[600] = pts[600], pts[0]
	pts[300].Timestamp = nil
	w, b := durationRepairWorker(cappedRun(), pts)
	if err := w.dispatch(context.Background(), durationRepairJob(t, drRunID)); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if got := b.durationRepair.updates[drRunID]; got != 3000 {
		t.Fatalf("duration written = %d, want 3000", got)
	}
}

func TestDurationRepair_KeepsTheCapWhenTheTrackCannotSayHowLong(t *testing.T) {
	untimed := timedTrack(10, 1, 3)
	for i := range untimed {
		untimed[i].Timestamp = nil
	}
	// 5 km in 600 s is 8.3 m/s: under the run ceiling. In 300 s it is 16.7
	// m/s, a track that covers part of the run.
	cases := map[string][]RecordedTrackPoint{
		"no timestamps":           untimed,
		"one timestamp":           timedTrack(1, 1, 3),
		"timestamps span nothing": timedTrack(5, 0, 3),
		"span too short for 5 km": timedTrack(301, 1, 5000.0/300.0),
		"span of ten days":        timedTrack(2, MaxRunDurationS, 0),
	}
	for name, track := range cases {
		t.Run(name, func(t *testing.T) {
			w, b := durationRepairWorker(cappedRun(), track)
			if err := w.dispatch(context.Background(), durationRepairJob(t, drRunID)); err != nil {
				t.Fatalf("dispatch: %v", err)
			}
			if len(b.durationRepair.updates) != 0 {
				t.Fatalf("wrote %v; the cap should stay", b.durationRepair.updates)
			}
		})
	}
}

func TestDurationRepair_SkipsWithoutWriting(t *testing.T) {
	unflagged := cappedRun()
	unflagged.Metadata = json.RawMessage(`{"duration_s_original": 44400094}`)
	trackless := cappedRun()
	trackless.TrackURL = nil
	missing := cappedRun()
	gone := "elsewhere/missing.json.gz"
	missing.TrackURL = &gone

	for name, run := range map[string]DurationRepairRun{
		"owner already corrected it": unflagged,
		"no track":                   trackless,
		"track object missing":       missing,
	} {
		t.Run(name, func(t *testing.T) {
			w, b := durationRepairWorker(run, timedTrack(1501, 2, 5000.0/3000.0))
			if err := w.dispatch(context.Background(), durationRepairJob(t, drRunID)); err != nil {
				t.Fatalf("dispatch: %v", err)
			}
			if len(b.durationRepair.updates) != 0 {
				t.Fatalf("wrote %v; nothing should be written", b.durationRepair.updates)
			}
		})
	}

	t.Run("run deleted", func(t *testing.T) {
		w, _ := durationRepairWorker(cappedRun(), nil)
		if err := w.dispatch(context.Background(), durationRepairJob(t, "11111111-2222-4333-8444-555555555555")); err != nil {
			t.Fatalf("dispatch: %v", err)
		}
	})
}

func TestDurationRepair_RereadsWhenTheRunChanged(t *testing.T) {
	w, b := durationRepairWorker(cappedRun(), timedTrack(1501, 2, 5000.0/3000.0))
	b.durationRepair.casMisses = 2
	if err := w.dispatch(context.Background(), durationRepairJob(t, drRunID)); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if got := b.durationRepair.updates[drRunID]; got != 3000 {
		t.Fatalf("duration written = %d, want 3000", got)
	}

	w, b = durationRepairWorker(cappedRun(), timedTrack(1501, 2, 5000.0/3000.0))
	b.durationRepair.casMisses = durationRepairMaxAttempts
	if err := w.dispatch(context.Background(), durationRepairJob(t, drRunID)); err == nil {
		t.Fatal("a run that changes on every attempt should fail the job")
	}
}

func TestDurationRepair_RefusesAPayloadForSomeoneElsesRun(t *testing.T) {
	w, b := durationRepairWorker(cappedRun(), timedTrack(1501, 2, 5000.0/3000.0))
	job := durationRepairJob(t, drRunID)
	job.Payload = json.RawMessage(`{"run_id":"` + drRunID + `","user_id":"99999999-2222-4333-8444-555555555555"}`)
	if err := w.dispatch(context.Background(), job); err == nil {
		t.Fatal("a payload naming another owner should fail")
	}
	if len(b.durationRepair.updates) != 0 {
		t.Fatalf("wrote %v", b.durationRepair.updates)
	}
}

// The wire shape of the write: duration_s only, conditional on the read's
// duration, track and flag.
func TestUpdateRunDuration_IsAConditionalPatchOfTheDurationAlone(t *testing.T) {
	var method, query string
	var body []byte
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		method = r.Method
		query = r.URL.Query().Encode()
		body, _ = io.ReadAll(r.Body)
		_, _ = w.Write([]byte(`[{"id":"` + drRunID + `"}]`))
	})
	run := cappedRun()
	if err := client.UpdateRunDuration(context.Background(), &run, 3000); err != nil {
		t.Fatalf("UpdateRunDuration: %v", err)
	}
	if method != http.MethodPatch {
		t.Fatalf("method = %s", method)
	}
	if string(body) != `{"duration_s":3000}` {
		t.Fatalf("body = %s", body)
	}
	for _, want := range []string{
		"duration_s=eq.864000",
		"id=eq." + drRunID,
		"metadata-%3E%3Eduration_repaired=eq.true",
		"track_url=eq.",
	} {
		if !strings.Contains(query, want) {
			t.Fatalf("query %q lacks %q", query, want)
		}
	}

	client = newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[]`))
	})
	if err := client.UpdateRunDuration(context.Background(), &run, 3000); !errors.Is(err, ErrRunChangedDuringDurationRepair) {
		t.Fatalf("a zero-row patch = %v, want ErrRunChangedDuringDurationRepair", err)
	}
}
