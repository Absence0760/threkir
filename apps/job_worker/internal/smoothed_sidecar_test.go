package internal

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

const drSidecar = drUserID + "/" + drRunID + ".smoothed.json.gz"

func TestSmoothedSidecarPathSitsBesideTheTrack(t *testing.T) {
	if got := smoothedSidecarPath(drUserID, drRunID); got != drSidecar {
		t.Errorf("path = %s, want %s", got, drSidecar)
	}
}

// The readers (web, Deno, Dart) replay fixtures/smoothed_sidecar_vectors.json;
// the writer must produce the fingerprint and the JSON shape they accept.
func TestSmoothedSidecar_WriterAgreesWithTheReadersVectors(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "fixtures", "smoothed_sidecar_vectors.json"))
	if err != nil {
		t.Fatal(err)
	}
	var vf struct {
		Version   int    `json:"version"`
		TrackJSON string `json:"trackJson"`
		SHA256    string `json:"sha256"`
		Cases     []struct {
			Name    string          `json:"name"`
			Sidecar json.RawMessage `json:"sidecar"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &vf); err != nil {
		t.Fatal(err)
	}
	if vf.Version != SmoothedSidecarVersion {
		t.Fatalf("vectors are for sidecar v%d; the writer writes v%d", vf.Version, SmoothedSidecarVersion)
	}
	if got := fingerprintTrack([]byte(vf.TrackJSON), 4); got.SHA256 != vf.SHA256 {
		t.Errorf("sha256 = %s, want the readers' %s", got.SHA256, vf.SHA256)
	}
	// The matching case decodes into the writer's own type and re-encodes to
	// the same object, so a renamed or retyped field fails here.
	var sc SmoothedSidecar
	if err := json.Unmarshal(vf.Cases[0].Sidecar, &sc); err != nil {
		t.Fatalf("the readers' sidecar is not the writer's shape: %v", err)
	}
	back, _ := json.Marshal(sc)
	var a, b any
	_ = json.Unmarshal(back, &a)
	_ = json.Unmarshal(vf.Cases[0].Sidecar, &b)
	if ja, jb := canonicalJSON(t, a), canonicalJSON(t, b); ja != jb {
		t.Errorf("writer re-encodes the readers' sidecar as %s, want %s", ja, jb)
	}
}

func canonicalJSON(t *testing.T, v any) string {
	t.Helper()
	out, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(out)
}

func TestDownloadRecordedTrack_FingerprintsTheDecompressedBytes(t *testing.T) {
	const body = `[{"lat":40,"lng":-75,"ts":"2026-10-08T07:00:00Z"},{"lat":40.0001,"lng":-75,"ts":"2026-10-08T07:00:01Z"}]`
	sum := sha256.Sum256([]byte(body))
	want := hex.EncodeToString(sum[:])
	var gz bytes.Buffer
	zw := gzip.NewWriter(&gz)
	_, _ = zw.Write([]byte(body))
	_ = zw.Close()
	for name, served := range map[string][]byte{"gzipped": gz.Bytes(), "plain": []byte(body)} {
		t.Run(name, func(t *testing.T) {
			client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
				_, _ = w.Write(served)
			})
			track, err := client.DownloadRecordedTrack(context.Background(), drTrack)
			if err != nil {
				t.Fatalf("download: %v", err)
			}
			if track.Fingerprint.Points != 2 || track.Fingerprint.SHA256 != want {
				t.Errorf("fingerprint = %+v, want {2 %s} — the hash is of the JSON a reader inflates, not of the gzip", track.Fingerprint, want)
			}
		})
	}
}

func TestUploadSmoothedSidecar_WireShape(t *testing.T) {
	var method, path, ctype, upsert string
	var body []byte
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		method, path = r.Method, r.URL.Path
		ctype, upsert = r.Header.Get("Content-Type"), r.Header.Get("x-upsert")
		zr, err := gzip.NewReader(r.Body)
		if err != nil {
			t.Errorf("body is not gzip: %v", err)
			return
		}
		body, _ = io.ReadAll(zr)
		_, _ = w.Write([]byte(`{}`))
	})
	sc := &SmoothedSidecar{Version: 1, Track: TrackFingerprint{Points: 2, SHA256: "ab"}, Positions: []*[2]float64{{40, -75}, nil}}
	if err := client.UploadSmoothedSidecar(context.Background(), drSidecar, sc); err != nil {
		t.Fatalf("upload: %v", err)
	}
	if method != http.MethodPost || path != "/storage/v1/object/runs/"+drSidecar {
		t.Errorf("%s %s", method, path)
	}
	if ctype != "application/gzip" || upsert != "true" {
		t.Errorf("Content-Type = %q, x-upsert = %q; the runs bucket admits only gzip and a rewrite must overwrite", ctype, upsert)
	}
	if string(bytes.TrimSpace(body)) != `{"version":1,"track":{"points":2,"sha256":"ab"},"positions":[[40,-75],null]}` {
		t.Errorf("body = %s", body)
	}
}

func TestBuildSmoothedSidecar_IndexesStoredWaypointsAndNamesTheTrack(t *testing.T) {
	stored := straightDopplerTrack(12, 2.5)
	stored[4].Lat = nil
	track := &RecordedTrack{Points: stored, Fingerprint: TrackFingerprint{Points: 12, SHA256: "f00"}}
	pts, idx := coordinatePointsIndexed(stored)
	replay := replayRecordedTrack(pts, 10)
	sc, why := buildSmoothedSidecar(track, idx, replay)
	if sc == nil {
		t.Fatalf("no sidecar: %s", why)
	}
	if sc.Version != 1 || sc.Track != track.Fingerprint || len(sc.Positions) != len(stored) {
		t.Fatalf("sidecar = %+v", sc)
	}
	if sc.Positions[4] != nil {
		t.Errorf("a waypoint without a coordinate must carry no position, got %v", *sc.Positions[4])
	}
	for k, i := range idx {
		want := replay.Positions[k]
		got := sc.Positions[i]
		if got == nil || got[0] != roundDeg7(want.Lat) || got[1] != roundDeg7(want.Lng) {
			t.Fatalf("stored index %d: %v, want the replay's position %v rounded", i, got, *want)
		}
	}
}

func TestBuildSmoothedSidecar_NoneForATrackThatCarriesItsOwnPair(t *testing.T) {
	stored := straightDopplerTrack(12, 2.5)
	stored[3].SmoothedLat, stored[3].SmoothedLng = f64(40.00001), f64(-75.00001)
	pts, idx := coordinatePointsIndexed(stored)
	if sc, _ := buildSmoothedSidecar(&RecordedTrack{Points: stored}, idx, replayRecordedTrack(pts, 10)); sc != nil {
		t.Error("a phone-saved track's own pair is what readers draw; no sidecar should shadow it")
	}
	stored[3].SmoothedLng = nil
	if sc, _ := buildSmoothedSidecar(&RecordedTrack{Points: stored}, idx, replayRecordedTrack(pts, 10)); sc == nil {
		t.Error("half a pair is no pair; the track still needs a sidecar")
	}
}

func TestDistanceRecompute_WritesTheSidecarOnTheSmoothedPass(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), straightDopplerTrack(101, 2.5))
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	sc := b.distance.sidecars[drSidecar]
	if sc == nil {
		t.Fatalf("no sidecar at %s; have %v", drSidecar, b.distance.sidecars)
	}
	raw, _ := json.Marshal(straightDopplerTrack(101, 2.5))
	if sc.Track != fingerprintTrack(raw, 101) || len(sc.Positions) != 101 {
		t.Errorf("sidecar names %+v over %d positions, want the downloaded track's fingerprint over 101", sc.Track, len(sc.Positions))
	}
}

func TestDistanceRecompute_NoSidecarOnTheForwardPass(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), legacyStopTrack())
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("handle: %v", err)
	}
	if b.distance.updates[0].Metadata["distance_estimator_pass"] != "forward" {
		t.Fatalf("fixture must take the forward pass")
	}
	if len(b.distance.sidecars) != 0 {
		t.Errorf("a forward-pass recompute keeps the raw line; got sidecars %v", b.distance.sidecars)
	}
	if len(b.storageDeleted) != 1 || len(b.storageDeleted[0]) != 1 || b.storageDeleted[0][0] != drSidecar {
		t.Errorf("deleted = %v, want the sidecar an earlier smoothed-pass recompute may have left", b.storageDeleted)
	}
}

func TestDistanceRecompute_StaleSidecarRemovalFailureDoesNotFailTheRecompute(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), legacyStopTrack())
	// The fake refuses every delete after the first storageDeleteErrAfter calls.
	b.storageDeleteErrAfter, b.storageDeleteCalls = 1, 1
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("the sidecar removal is auxiliary to the distance; got %v", err)
	}
	if len(b.distance.updates) != 1 || len(b.storageDeleted) != 0 {
		t.Errorf("updates = %d, deleted = %v; want the distance written and the refused delete logged", len(b.distance.updates), b.storageDeleted)
	}
}

func TestDistanceRecompute_SidecarFailureDoesNotFailTheRecompute(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), straightDopplerTrack(101, 2.5))
	b.distance.uploadErr = &HTTPError{StatusCode: http.StatusServiceUnavailable}
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err != nil {
		t.Fatalf("the sidecar is auxiliary to the distance; got %v", err)
	}
	if len(b.distance.updates) != 1 {
		t.Fatalf("updates = %d, want the distance written", len(b.distance.updates))
	}
}

func TestDistanceRecompute_NoSidecarWhenTheWriteNeverLands(t *testing.T) {
	w, b := distanceWorker(t, appRun(`{}`), straightDopplerTrack(11, 2.5))
	b.distance.casMisses = distanceRecomputeMaxAttempts
	if err := w.handleDistanceRecompute(context.Background(), distanceJob(t, DistanceRecomputePayload{RunID: drRunID})); err == nil {
		t.Fatal("want the attempts-exhausted error")
	}
	if len(b.distance.sidecars) != 0 {
		t.Error("a recompute whose distance never landed must not write a sidecar")
	}
}

// watchSidecarWorker is a map_match worker for a run at the road test's
// track path, whose stored track (with or without Doppler) is recorded.
func watchSidecarWorker(t *testing.T, run *RoadDistanceRun, recorded []RecordedTrackPoint, m Matcher) (*Worker, *fakeBackend, *Job) {
	t.Helper()
	b := newFakeBackend()
	b.trackURL = *run.TrackURL
	b.trackByPath[*run.TrackURL] = roadTrack(201)
	b.road = &fakeRoadDistance{runs: map[string]*RoadDistanceRun{run.ID: run}}
	b.distance = &fakeDistanceRecompute{tracks: map[string][]RecordedTrackPoint{*run.TrackURL: recorded}}
	job := &Job{ID: 1, Kind: "map_match", Payload: mustPayload(t, MapMatchPayload{RunID: run.ID, UserID: "user-1"})}
	return newTestWorker(b, m), b, job
}

func watchRun(meta string) *RoadDistanceRun {
	r := roadRun(meta)
	r.UserID, r.Source = "user-1", "watch"
	return r
}

func TestMapMatch_WritesTheSidecarForAWatchRun(t *testing.T) {
	w, b, job := watchSidecarWorker(t, watchRun(`{}`), straightDopplerTrack(60, 2.5), fakeRoadMatcher{})
	if err := w.handleMapMatch(context.Background(), job); err != nil {
		t.Fatal(err)
	}
	sc := b.distance.sidecars["user-1/run-1.smoothed.json.gz"]
	if sc == nil || len(sc.Positions) != 60 {
		t.Fatalf("sidecars = %v, want one for the watch run's 60 waypoints", b.distance.sidecars)
	}
}

func TestMapMatch_SidecarRules(t *testing.T) {
	cases := []struct {
		name     string
		run      *RoadDistanceRun
		recorded []RecordedTrackPoint
		matcher  Matcher
		want     bool
	}{
		{"phone run: the phone saves its own pair", func() *RoadDistanceRun { r := watchRun(`{}`); r.Source = "app"; return r }(),
			straightDopplerTrack(60, 2.5), fakeRoadMatcher{}, false},
		{"import", func() *RoadDistanceRun { r := watchRun(`{}`); r.Source = "strava"; return r }(),
			straightDopplerTrack(60, 2.5), fakeRoadMatcher{}, false},
		{"in progress", watchRun(`{"in_progress":true}`), straightDopplerTrack(60, 2.5), fakeRoadMatcher{}, false},
		{"position-only, not a road run", watchRun(`{}`), legacyStopTrack(), fakeRoadMatcher{}, false},
		{"position-only road run", func() *RoadDistanceRun {
			r := watchRun(`{}`)
			r.DistanceM = 360
			return r
		}(), legacyStopTrack(), fakeRoadMatcher{road: roadOf(358, 0.9)}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w, b, job := watchSidecarWorker(t, tc.run, tc.recorded, tc.matcher)
			if err := w.handleMapMatch(context.Background(), job); err != nil {
				t.Fatal(err)
			}
			if got := len(b.distance.sidecars) == 1; got != tc.want {
				t.Errorf("sidecar written = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestMapMatch_SidecarFailureNeverFailsTheMatch(t *testing.T) {
	w, b, job := watchSidecarWorker(t, watchRun(`{}`), straightDopplerTrack(60, 2.5), fakeRoadMatcher{})
	b.distance.downloadErr = errors.New("storage down")
	if err := w.handleMapMatch(context.Background(), job); err != nil {
		t.Fatalf("the sidecar is auxiliary to the match; got %v", err)
	}
	if len(b.uploaded) != 1 {
		t.Errorf("matched track uploads = %d, want the match persisted", len(b.uploaded))
	}
}
