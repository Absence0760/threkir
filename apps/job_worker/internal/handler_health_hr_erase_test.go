package internal

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"io"
	"sort"
	"strings"
	"testing"
	"time"
)

type fakeHealthErase struct {
	runs    []HealthEraseRun
	objects map[string][]byte
	listErr error
	// uploads records each rewritten path, in order.
	uploads []string
}

func (f *fakeBackend) HealthDataConsented(_ context.Context, userID string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.healthConsentErr != nil {
		return false, f.healthConsentErr
	}
	return f.healthConsented[userID], nil
}

func (f *fakeBackend) ListRunsForHealthErase(_ context.Context, _ string, afterID string, limit int) ([]HealthEraseRun, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.healthErase == nil {
		return nil, errors.New("fakeBackend: no healthErase state")
	}
	if f.healthErase.listErr != nil {
		return nil, f.healthErase.listErr
	}
	runs := append([]HealthEraseRun(nil), f.healthErase.runs...)
	sort.Slice(runs, func(i, j int) bool { return runs[i].ID < runs[j].ID })
	var out []HealthEraseRun
	for _, r := range runs {
		if r.ID > afterID {
			out = append(out, r)
		}
		if len(out) == limit {
			break
		}
	}
	return out, nil
}

func (f *fakeBackend) DownloadRunsObject(_ context.Context, path string) ([]byte, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.healthErase == nil {
		return nil, errors.New("fakeBackend: no healthErase state")
	}
	b, ok := f.healthErase.objects[path]
	if !ok {
		return nil, &HTTPError{StatusCode: 404, Method: "GET", Endpoint: path}
	}
	return b, nil
}

func (f *fakeBackend) UploadRunsObject(_ context.Context, path string, body []byte, _ string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.healthErase == nil {
		return errors.New("fakeBackend: no healthErase state")
	}
	f.healthErase.objects[path] = body
	f.healthErase.uploads = append(f.healthErase.uploads, path)
	return nil
}

const heUser = "00000000-0000-0000-0000-0000000b7ac3"

func gz(t *testing.T, s string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write([]byte(s)); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func ungz(t *testing.T, b []byte) string {
	t.Helper()
	zr, err := gzip.NewReader(bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	out, err := io.ReadAll(zr)
	if err != nil {
		t.Fatal(err)
	}
	return string(out)
}

func healthEraseJob(t *testing.T, userID string) *Job {
	t.Helper()
	raw, err := json.Marshal(HealthHrErasePayload{UserID: userID})
	if err != nil {
		t.Fatal(err)
	}
	return &Job{ID: 91, Kind: "health_hr_erase", Payload: raw, Attempts: 1}
}

func TestHealthHrErase_StripsBpmAndDeletesSidecars(t *testing.T) {
	withHR := heUser + "/r1.json.gz"
	noHR := heUser + "/r2.json.gz"
	b := &fakeBackend{storageObjects: map[string][]StorageObject{}, healthErase: &fakeHealthErase{
		runs: []HealthEraseRun{
			{ID: "r1", TrackURL: strp(withHR)},
			{ID: "r2", TrackURL: strp(noHR)},
			{ID: "r3"},
		},
		objects: map[string][]byte{
			withHR: gz(t, `[{"lat":1,"lng":2,"bpm":150,"ts":"2026-01-01T00:00:00Z"},{"lat":1.1,"lng":2.1}]`),
			noHR:   gz(t, `[{"lat":1,"lng":2}]`),
		},
	}}
	w := newTestWorker(b, nil)
	if err := w.dispatch(context.Background(), healthEraseJob(t, heUser)); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	got := ungz(t, b.healthErase.objects[withHR])
	if strings.Contains(got, "bpm") || !strings.Contains(got, `"ts":"2026-01-01T00:00:00Z"`) {
		t.Fatalf("rewritten track = %s; want every key but bpm", got)
	}
	if len(b.healthErase.uploads) != 1 || b.healthErase.uploads[0] != withHR {
		t.Fatalf("uploads = %v; only the track carrying bpm is rewritten", b.healthErase.uploads)
	}
	want := []string{heUser + "/r1.hr.json.gz", heUser + "/r2.hr.json.gz", heUser + "/r3.hr.json.gz"}
	if len(b.storageDeleted) != 1 || strings.Join(b.storageDeleted[0], ",") != strings.Join(want, ",") {
		t.Fatalf("sidecar deletes = %v; want %v", b.storageDeleted, want)
	}
}

func TestHealthHrErase_LeavesARunThatHoldsHeartRateAgain(t *testing.T) {
	path := heUser + "/r1.json.gz"
	body := gz(t, `[{"lat":1,"lng":2,"bpm":150}]`)
	b := &fakeBackend{storageObjects: map[string][]StorageObject{}, healthErase: &fakeHealthErase{
		runs:    []HealthEraseRun{{ID: "r1", TrackURL: strp(path), HasHR: true}},
		objects: map[string][]byte{path: body},
	}}
	w := newTestWorker(b, nil)
	if err := w.dispatch(context.Background(), healthEraseJob(t, heUser)); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if len(b.healthErase.uploads) != 0 || len(b.storageDeleted) != 0 {
		t.Fatalf("a run stored under renewed consent must be left alone; uploads=%v deletes=%v",
			b.healthErase.uploads, b.storageDeleted)
	}
}

func TestHealthHrErase_MissingTrackIsNotAnError(t *testing.T) {
	b := &fakeBackend{storageObjects: map[string][]StorageObject{}, healthErase: &fakeHealthErase{
		runs:    []HealthEraseRun{{ID: "r1", TrackURL: strp(heUser + "/gone.json.gz")}},
		objects: map[string][]byte{},
	}}
	w := newTestWorker(b, nil)
	if err := w.dispatch(context.Background(), healthEraseJob(t, heUser)); err != nil {
		t.Fatalf("a missing object must not fail the job: %v", err)
	}
}

func TestHealthHrErase_PagesPastTheFirstPage(t *testing.T) {
	var runs []HealthEraseRun
	for i := 0; i < healthErasePage+5; i++ {
		runs = append(runs, HealthEraseRun{ID: time.Unix(int64(i), 0).UTC().Format("20060102150405")})
	}
	b := &fakeBackend{storageObjects: map[string][]StorageObject{}, healthErase: &fakeHealthErase{runs: runs, objects: map[string][]byte{}}}
	w := newTestWorker(b, nil)
	if err := w.dispatch(context.Background(), healthEraseJob(t, heUser)); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	n := 0
	for _, batch := range b.storageDeleted {
		n += len(batch)
	}
	if n != healthErasePage+5 {
		t.Fatalf("sidecar paths cleared = %d; want every run's", n)
	}
}

func TestHealthHrErase_RefusesABadPayload(t *testing.T) {
	w := newTestWorker(&fakeBackend{}, nil)
	if err := w.dispatch(context.Background(), healthEraseJob(t, "not-a-uuid")); err == nil {
		t.Fatal("a non-uuid user_id must fail the job")
	}
}

func TestStripTrackBpm_LeavesATrackWithoutBpmAlone(t *testing.T) {
	_, changed, err := stripTrackBpm([]byte(`[{"lat":1,"lng":2}]`))
	if err != nil || changed {
		t.Fatalf("changed=%v err=%v; a track with no bpm is not rewritten", changed, err)
	}
	if _, _, err := stripTrackBpm([]byte(`{"not":"an array"}`)); err == nil {
		t.Fatal("a non-array body must be refused, not rewritten")
	}
}

func TestStravaEvent_DropsTheHeartRateStreamWithoutConsent(t *testing.T) {
	for _, tc := range []struct {
		name      string
		consented bool
		err       error
		wantBpm   bool
	}{
		{"no consent", false, nil, false},
		{"consent", true, nil, true},
		{"lookup failed", true, errors.New("down"), false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			be := newFakeBackend()
			be.integrationByAthlete[200] = "user-A"
			be.tokensByUser["user-A"] = TokenPair{AccessToken: "at-A", RefreshToken: "rt-A"}
			be.healthConsented = map[string]bool{"user-A": tc.consented}
			be.healthConsentErr = tc.err
			st := &fakeStrava{
				byActivity: map[int64]StravaActivityResult{
					100: {Status: StravaFetchOK, Activity: &StravaActivity{
						ID: 100, Name: "Morning Run", Distance: 5000, MovingTime: 1500,
						ElapsedTime: 1600, StartDate: "2026-05-11T10:00:00Z", Type: "Run", SportType: "Run",
					}},
				},
				streamsByActivity: map[int64]map[string]StravaStream{
					100: {
						"latlng":    {Data: []json.RawMessage{json.RawMessage(`[51.5,-0.1]`), json.RawMessage(`[51.6,-0.2]`)}},
						"time":      {Data: []json.RawMessage{json.RawMessage(`0`), json.RawMessage(`5`)}},
						"heartrate": {Data: []json.RawMessage{json.RawMessage(`140`), json.RawMessage(`145`)}},
					},
				},
			}
			be.jobs = []*Job{{
				ID: 1, Kind: "strava_event",
				Payload: stravaEventPayload(t, StravaEventPayload{
					ObjectType: "activity", AspectType: "create",
					ObjectID: 100, OwnerID: 200, EventTime: time.Now().Unix(),
				}),
			}}
			w := newStravaWorker(be, st)
			ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
			defer cancel()
			_ = w.Run(ctx)
			if len(be.uploaded) != 1 {
				t.Fatalf("the run's track must still upload; got %d uploads", len(be.uploaded))
			}
			for _, pts := range be.uploaded {
				hasBpm := pts[0].Bpm != nil
				if hasBpm != tc.wantBpm {
					t.Fatalf("track bpm present = %v; want %v", hasBpm, tc.wantBpm)
				}
			}
		})
	}
}
