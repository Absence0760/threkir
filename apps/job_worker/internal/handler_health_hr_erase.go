package internal

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// HealthHrErasePayload is what private.erase_health_records enqueues for
// kind='health_hr_erase' (migration 20271227100008, decisions § 2514): one
// runner whose health-data consent was withdrawn, or whose held backlog the
// purge erased.
type HealthHrErasePayload struct {
	UserID string `json:"user_id"`
}

// HealthEraseRun is the slice of a run the erase reads: where its track and
// sidecar live, and whether the row holds heart rate right now.
type HealthEraseRun struct {
	ID          string  `json:"id"`
	TrackURL    *string `json:"track_url"`
	HRSeriesURL *string `json:"hr_series_url"`
	// HasHR is true when the row carries a heart-rate key or a sidecar path.
	// The database keeps those only under consent, so a run that has one was
	// stored after the runner consented again and is left alone.
	HasHR bool `json:"-"`
}

const healthErasePage = 200

// handleHealthHrErase erases the Storage copies of a runner's heart rate,
// which SQL cannot reach: every {user_id}/{run_id}.hr.json.gz sidecar, and
// the per-point bpm inside each {user_id}/{run_id}.json.gz track. The rows
// were erased in the withdrawal's own transaction. A run that holds heart
// rate again (consent given again since) is skipped, so the blob keeps
// agreeing with its row. Idempotent: a retry finds nothing left to strip.
func (w *Worker) handleHealthHrErase(ctx context.Context, job *Job) error {
	var p HealthHrErasePayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if !reRunUUID.MatchString(p.UserID) {
		return fmt.Errorf("payload user_id %q is not a uuid", p.UserID)
	}

	after := ""
	scrubbed, sidecars := 0, 0
	for {
		runs, err := w.Backend.ListRunsForHealthErase(ctx, p.UserID, after, healthErasePage)
		if err != nil {
			return fmt.Errorf("list runs: %w", err)
		}
		if len(runs) == 0 {
			break
		}
		var paths []string
		for _, r := range runs {
			if r.HasHR {
				continue
			}
			paths = append(paths, p.UserID+"/"+r.ID+".hr.json.gz")
			if r.TrackURL == nil || *r.TrackURL == "" {
				continue
			}
			changed, err := w.scrubTrackHeartRate(ctx, *r.TrackURL)
			if err != nil {
				return fmt.Errorf("run %s track: %w", r.ID, err)
			}
			if changed {
				scrubbed++
			}
		}
		if len(paths) > 0 {
			if err := w.Backend.DeleteStorageObjects(ctx, schema.BucketRuns, paths); err != nil {
				return fmt.Errorf("delete sidecars: %w", err)
			}
			sidecars += len(paths)
		}
		after = runs[len(runs)-1].ID
		if len(runs) < healthErasePage {
			break
		}
	}
	w.Log.Info("health heart rate erased from storage",
		"user_id", p.UserID, "tracks_rewritten", scrubbed, "sidecar_paths_cleared", sidecars)
	return nil
}

// scrubTrackHeartRate rewrites one stored track without its per-point bpm.
// It reports false when the track carries none, is missing, or is not a
// JSON array (nothing this job may safely rewrite).
func (w *Worker) scrubTrackHeartRate(ctx context.Context, path string) (bool, error) {
	body, err := w.Backend.DownloadRunsObject(ctx, path)
	var hErr *HTTPError
	if errors.As(err, &hErr) && (hErr.StatusCode == http.StatusNotFound || hErr.StatusCode == http.StatusBadRequest) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	out, changed, err := stripTrackBpm(body)
	if err != nil {
		w.Log.Warn("health erase left a track it could not parse", "path", path, "err", err)
		return false, nil
	}
	if !changed {
		return false, nil
	}
	if err := w.Backend.UploadRunsObject(ctx, path, out, "application/gzip"); err != nil {
		return false, err
	}
	return true, nil
}

// stripTrackBpm removes the `bpm` key from every point of a stored track
// (gzipped or plain JSON) and returns the gzipped result. Every other key is
// kept as it was.
func stripTrackBpm(body []byte) ([]byte, bool, error) {
	raw, err := gunzipIfGzipped(body)
	if err != nil {
		return nil, false, err
	}
	var pts []map[string]json.RawMessage
	if err := json.Unmarshal(raw, &pts); err != nil {
		return nil, false, err
	}
	changed := false
	for _, pt := range pts {
		if _, ok := pt["bpm"]; ok {
			delete(pt, "bpm")
			changed = true
		}
	}
	if !changed {
		return nil, false, nil
	}
	enc, err := json.Marshal(pts)
	if err != nil {
		return nil, false, err
	}
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(enc); err != nil {
		return nil, false, err
	}
	if err := zw.Close(); err != nil {
		return nil, false, err
	}
	return buf.Bytes(), true, nil
}
