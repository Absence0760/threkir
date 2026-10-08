package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"regexp"
	"time"

	"github.com/Absence0760/threkir/apps/job_worker/internal/gpsdistance"
	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// DistanceRecomputePayload is the payload `request_distance_recompute`
// writes for kind='distance_recompute' jobs — the map_match shape. The
// handler reads the run's owner from the row; a user_id in the payload,
// when present, must agree with it.
type DistanceRecomputePayload struct {
	RunID  string `json:"run_id"`
	UserID string `json:"user_id,omitempty"`
}

// DistanceEstimatorV1 is the value stamped in metadata.distance_estimator.
const DistanceEstimatorV1 = "kalman_v1"

// distanceRecomputeMaxAttempts bounds the re-read loop when the CAS on
// track_url + metadata misses because the run changed under the worker.
const distanceRecomputeMaxAttempts = 3

var reRunUUID = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// appRecordedSources are the runs.source values whose distance this
// estimator owns: the phone recorder ('app') and our own watch apps
// ('watch'). Everything else is an import that arrived with a distance
// its provider measured — Strava, Garmin, HealthKit, Health Connect,
// parkrun and race results — and overwriting it would replace the
// provider's figure with one computed from a track the provider never
// used for it.
var appRecordedSources = map[string]bool{"app": true, "watch": true}

// maxSpeedMpsForActivity mirrors ActivityType.maxSpeedMps in
// packages/core_models/lib/src/activity_type.dart. An unknown or empty
// type takes the run ceiling, which is also the column's default.
func maxSpeedMpsForActivity(activityType string) float64 {
	switch activityType {
	case "walk":
		return 5
	case "cycle":
		return 25
	case "hike":
		return 6
	case "stroller":
		return 9
	default:
		return 10
	}
}

// handleDistanceRecompute replays a stored track through the spec-v1
// estimator and rewrites runs.distance_m, keeping the originally
// recorded figure in metadata.distance_recorded_m.
func (w *Worker) handleDistanceRecompute(ctx context.Context, job *Job) error {
	var p DistanceRecomputePayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if !reRunUUID.MatchString(p.RunID) {
		return fmt.Errorf("payload run_id %q is not a uuid", p.RunID)
	}

	for attempt := 1; attempt <= distanceRecomputeMaxAttempts; attempt++ {
		run, err := w.Backend.ReadRunForDistanceRecompute(ctx, p.RunID)
		if errors.Is(err, ErrRunNotFound) {
			w.Log.Info("distance recompute skipped", "run_id", p.RunID, "reason", "run no longer exists")
			return nil
		}
		if err != nil {
			return fmt.Errorf("read run: %w", err)
		}
		if p.UserID != "" && p.UserID != run.UserID {
			return fmt.Errorf("payload user_id does not own run %s", p.RunID)
		}
		meta, err := decodeRunMetadata(run.Metadata)
		if err != nil {
			return fmt.Errorf("run %s metadata: %w", p.RunID, err)
		}
		if reason := distanceRecomputeSkipReason(run, meta); reason != "" {
			w.Log.Info("distance recompute skipped", "run_id", p.RunID, "reason", reason)
			return nil
		}

		pts, err := w.Backend.DownloadRecordedTrack(ctx, *run.TrackURL)
		if err != nil {
			return fmt.Errorf("download track: %w", err)
		}
		fixes := recordedTrackFixes(pts)
		if len(fixes) < 2 {
			return fmt.Errorf("track %s has %d timestamped waypoints; need at least 2", *run.TrackURL, len(fixes))
		}
		est := gpsdistance.New(maxSpeedMpsForActivity(run.ActivityType))
		for _, f := range fixes {
			est.AddFix(f)
		}
		est.Finish(fixes[len(fixes)-1].T)
		distanceM := math.Round(est.DistanceM()*100) / 100

		merged, err := mergeDistanceMetadata(meta, run.DistanceM, time.Now().UTC())
		if err != nil {
			return err
		}
		err = w.Backend.UpdateRunDistance(ctx, run, distanceM, merged)
		if errors.Is(err, ErrRunChangedDuringRecompute) {
			w.Log.Info("run changed during distance recompute; re-reading",
				"run_id", p.RunID, "attempt", attempt)
			continue
		}
		if err != nil {
			return fmt.Errorf("update run distance: %w", err)
		}
		w.Log.Info("distance recomputed",
			"run_id", p.RunID,
			"previous_m", run.DistanceM,
			"distance_m", distanceM,
			"fixes", len(fixes),
		)
		return nil
	}
	return fmt.Errorf("run %s changed on each of %d attempts; not recomputed", p.RunID, distanceRecomputeMaxAttempts)
}

func decodeRunMetadata(raw json.RawMessage) (map[string]json.RawMessage, error) {
	meta := map[string]json.RawMessage{}
	if isJSONNull(raw) {
		return meta, nil
	}
	if err := json.Unmarshal(raw, &meta); err != nil {
		return nil, fmt.Errorf("not a json object: %w", err)
	}
	return meta, nil
}

func metaIsTrue(meta map[string]json.RawMessage, key string) bool {
	var b bool
	return json.Unmarshal(meta[key], &b) == nil && b
}

func metaString(meta map[string]json.RawMessage, key string) string {
	var s string
	if json.Unmarshal(meta[key], &s) != nil {
		return ""
	}
	return s
}

// distanceRecomputeSkipReason returns why a run's distance is not the
// estimator's to replace, or "" when it is.
func distanceRecomputeSkipReason(run *DistanceRecomputeRun, meta map[string]json.RawMessage) string {
	switch {
	case run.TrackURL == nil || *run.TrackURL == "":
		return "no track"
	case !appRecordedSources[run.Source]:
		return "source " + run.Source + " is an import with its own distance"
	case metaIsTrue(meta, schema.MetaInProgress):
		return "run is still in progress"
	case metaIsTrue(meta, schema.MetaManualEntry):
		return "manual entry"
	case metaIsTrue(meta, schema.MetaIndoor) || metaIsTrue(meta, schema.MetaIndoorEstimated):
		return "indoor run"
	case metaString(meta, schema.MetaDistanceSource) != "":
		// pedometer / treadmill today; any provenance tag names a
		// non-GPS source, and an unknown one is not ours to overwrite.
		return "distance came from " + metaString(meta, schema.MetaDistanceSource)
	case meta[schema.MetaDistanceEstimator] != nil && meta[schema.MetaDistanceRecomputedAt] == nil:
		// Stamped by a recorder that ran the estimator live over every
		// fix; the stored track is movement-gated, so a replay would see
		// fewer fixes than the live figure did.
		return "recorded live by " + metaString(meta, schema.MetaDistanceEstimator)
	}
	return ""
}

// recordedTrackFixes turns stored waypoints into estimator fixes, in
// order, with t in seconds since the first timestamped waypoint.
// Waypoints without a timestamp or a coordinate are skipped.
func recordedTrackFixes(pts []RecordedTrackPoint) []gpsdistance.Fix {
	fixes := make([]gpsdistance.Fix, 0, len(pts))
	var t0 time.Time
	for _, p := range pts {
		if p.Timestamp == nil || p.Lat == nil || p.Lng == nil {
			continue
		}
		if len(fixes) == 0 {
			t0 = *p.Timestamp
		}
		fixes = append(fixes, gpsdistance.Fix{
			T:                p.Timestamp.Sub(t0).Seconds(),
			Lat:              *p.Lat,
			Lng:              *p.Lng,
			AccuracyM:        p.AccuracyM,
			SpeedMps:         p.SpeedMps,
			SpeedAccuracyMps: p.SpeedAccuracyMps,
			BearingDeg:       p.BearingDeg,
		})
	}
	return fixes
}

// mergeDistanceMetadata adds the recompute's three keys to the bag and
// leaves every other key byte-for-byte as read. distance_recorded_m keeps
// an existing value so a repeated recompute never overwrites the
// recorder's original figure with a previous recompute's.
func mergeDistanceMetadata(meta map[string]json.RawMessage, previousDistanceM float64, now time.Time) (json.RawMessage, error) {
	out := make(map[string]json.RawMessage, len(meta)+3)
	for k, v := range meta {
		out[k] = v
	}
	if v, ok := out[schema.MetaDistanceRecordedM]; !ok || isJSONNull(v) {
		raw, err := json.Marshal(previousDistanceM)
		if err != nil {
			return nil, err
		}
		out[schema.MetaDistanceRecordedM] = raw
	}
	est, _ := json.Marshal(DistanceEstimatorV1)
	out[schema.MetaDistanceEstimator] = est
	at, _ := json.Marshal(now.Format(time.RFC3339))
	out[schema.MetaDistanceRecomputedAt] = at
	return json.Marshal(out)
}
