package internal

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// The smoothed-position sidecar: `{user_id}/{run_id}.smoothed.json.gz` in the
// `runs` bucket, holding the spec-v1.2 smoother's position for each stored
// waypoint of a track the worker replayed (docs/features/gps_distance.md
// § Waypoint fields). The worker cannot write the pair into the track itself:
// Storage has no conditional upload and clients overwrite the same object
// path, so a rewrite could clobber a newer upload unseen. Instead the sidecar
// names the exact track bytes it was computed from, and every reader merges it
// only when that fingerprint matches the track it holds — a re-uploaded track
// silently falls back to its own (raw or phone-smoothed) positions. The run
// records the hash in metadata.smoothed_sidecar_sha256 while the sidecar is
// stored, so a reader fetches it only for a run that has one, for the track
// it holds, rather than asking Storage for every run.
//
// Readers: web `lib/runs/smoothed_sidecar.ts`, Deno
// `_shared/smoothed_sidecar.ts` (clip-public-track, which merges before the
// privacy-zone clip), Dart `packages/api_client/lib/src/smoothed_sidecar.dart`.

// SmoothedSidecarVersion is the sidecar format the readers accept.
const SmoothedSidecarVersion = 1

// TrackFingerprint identifies the decompressed bytes of one stored track.
type TrackFingerprint struct {
	Points int    `json:"points"`
	SHA256 string `json:"sha256"`
}

// SmoothedSidecar is the object's JSON. Positions has one entry per stored
// waypoint, `[lat, lng]` in degrees or null where the smoother placed none (a
// waypoint without a coordinate or a timestamp, an ignored fix).
type SmoothedSidecar struct {
	Version   int              `json:"version"`
	Track     TrackFingerprint `json:"track"`
	Positions []*[2]float64    `json:"positions"`
}

// RecordedTrack is a downloaded track with the fingerprint of its bytes.
type RecordedTrack struct {
	Points      []RecordedTrackPoint
	Fingerprint TrackFingerprint
}

func smoothedSidecarPath(userID, runID string) string {
	return userID + "/" + runID + ".smoothed.json.gz"
}

// fingerprintTrack is the fingerprint of a track whose decompressed JSON is
// decompressed and which decodes to points waypoints.
func fingerprintTrack(decompressed []byte, points int) TrackFingerprint {
	sum := sha256.Sum256(decompressed)
	return TrackFingerprint{Points: points, SHA256: hex.EncodeToString(sum[:])}
}

// coordinatePointsIndexed is coordinatePoints plus, for each kept point, its
// index in pts.
func coordinatePointsIndexed(pts []RecordedTrackPoint) ([]RecordedTrackPoint, []int) {
	out := make([]RecordedTrackPoint, 0, len(pts))
	idx := make([]int, 0, len(pts))
	for i, p := range pts {
		if p.Lat != nil && p.Lng != nil {
			out = append(out, p)
			idx = append(idx, i)
		}
	}
	return out, idx
}

func finiteF64(p *float64) bool { return p != nil && !math.IsNaN(*p) && !math.IsInf(*p, 0) }

// roundDeg7 rounds degrees to 1e-7 (about 1 cm), which the line never needs
// finer and which keeps the object small.
func roundDeg7(v float64) float64 { return math.Round(v*1e7) / 1e7 }

// buildSmoothedSidecar returns the sidecar for track from replay, where
// storedIdx maps each replayed point to its index in track.Points, or nil and
// why there is none: the track already carries its own pair on some waypoint
// (a phone save, whose positions every reader prefers), or the smoother
// placed no position.
func buildSmoothedSidecar(track *RecordedTrack, storedIdx []int, replay trackReplay) (*SmoothedSidecar, string) {
	for _, p := range track.Points {
		if finiteF64(p.SmoothedLat) && finiteF64(p.SmoothedLng) {
			return nil, "track already carries smoothed positions"
		}
	}
	positions := make([]*[2]float64, len(track.Points))
	placed := 0
	for k, i := range storedIdx {
		if k >= len(replay.Positions) || replay.Positions[k] == nil {
			continue
		}
		p := replay.Positions[k]
		positions[i] = &[2]float64{roundDeg7(p.Lat), roundDeg7(p.Lng)}
		placed++
	}
	if placed == 0 {
		return nil, "the smoother placed no position"
	}
	return &SmoothedSidecar{Version: SmoothedSidecarVersion, Track: track.Fingerprint, Positions: positions}, ""
}

// uploadSmoothedSidecar uploads the sidecar for a replayed track and returns
// the fingerprint hash it was built for, or "" when there is none to write or
// the upload failed. It is auxiliary to whatever the caller writes (the
// recomputed distance, the matched track), so a failure is logged and never
// returned; the caller records the hash on the run
// (metadata.smoothed_sidecar_sha256) only when it is non-empty, so the key
// never names a sidecar this call did not store.
func (w *Worker) uploadSmoothedSidecar(
	ctx context.Context, userID, runID string, track *RecordedTrack, storedIdx []int, replay trackReplay,
) string {
	sc, why := buildSmoothedSidecar(track, storedIdx, replay)
	if sc == nil {
		w.Log.Info("smoothed sidecar skipped", "run_id", runID, "reason", why)
		return ""
	}
	if err := w.Backend.UploadSmoothedSidecar(ctx, smoothedSidecarPath(userID, runID), sc); err != nil {
		w.Log.Warn("smoothed sidecar upload failed", "run_id", runID, "err", err)
		return ""
	}
	return sc.Track.SHA256
}

// withSmoothedSidecarKey returns a copy of meta with
// smoothed_sidecar_sha256 set to sha, or removed when sha is "".
func withSmoothedSidecarKey(meta map[string]json.RawMessage, sha string) map[string]json.RawMessage {
	out := make(map[string]json.RawMessage, len(meta)+1)
	for k, v := range meta {
		out[k] = v
	}
	if sha == "" {
		delete(out, schema.MetaSmoothedSidecarSHA256)
	} else {
		enc, _ := json.Marshal(sha)
		out[schema.MetaSmoothedSidecarSHA256] = enc
	}
	return out
}

const smoothedSidecarKeyMaxAttempts = 3

// recordSmoothedSidecar sets metadata.smoothed_sidecar_sha256 to sha on the
// run while it still holds trackURL, the map_match watch step's record of the
// sidecar it just uploaded. The same read-modify-write as updateRoadDistance:
// conditional on the bag and the track_url read, re-read on a miss, and it
// carries every other key (distance_recomputed_at included) so the
// runs_keep_distance_recompute trigger leaves it alone.
func (w *Worker) recordSmoothedSidecar(ctx context.Context, runID, trackURL, sha string) error {
	for attempt := 1; attempt <= smoothedSidecarKeyMaxAttempts; attempt++ {
		run, err := w.Backend.ReadRunForRoadDistance(ctx, runID)
		if errors.Is(err, ErrRunNotFound) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("read run: %w", err)
		}
		if run.TrackURL == nil || *run.TrackURL != trackURL {
			return nil
		}
		meta, err := decodeRunMetadata(run.Metadata)
		if err != nil {
			return fmt.Errorf("run %s metadata: %w", runID, err)
		}
		if metaString(meta, schema.MetaSmoothedSidecarSHA256) == sha {
			return nil
		}
		merged, err := json.Marshal(withSmoothedSidecarKey(meta, sha))
		if err != nil {
			return err
		}
		err = w.Backend.UpdateRunMetadata(ctx, run, trackURL, merged)
		if errors.Is(err, ErrRunMetadataChanged) {
			continue
		}
		if err != nil {
			return fmt.Errorf("update run metadata: %w", err)
		}
		return nil
	}
	return fmt.Errorf("run %s changed on each of %d attempts; smoothed sidecar not recorded", runID, smoothedSidecarKeyMaxAttempts)
}
