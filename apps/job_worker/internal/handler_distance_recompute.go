package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"regexp"
	"time"

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

// DistanceEstimatorV2 is the value stamped in metadata.distance_estimator:
// the spec-v1.2 smoother. "kalman_v1" was the v1 / v1.1 forward filter; a
// run recomputed under it is eligible again (the skip below looks only at
// whether a recompute has ever stamped the run, not at which estimator).
const DistanceEstimatorV2 = "kalman_v2"

// The two values of metadata.distance_estimator_pass: which of the
// smoother's passes the recompute kept. A track with Doppler always keeps
// the smoothed figure. A position-only track keeps it only on a road run:
// off road the constant-velocity model cuts corners, and the backward pass
// cuts them more than the forward filter (the bench's position-only forest
// trail -3.1% smoothed against -1.2% forward, 12 s switchbacks -31% against
// -21%), so the forward figure is kept until the ground-truth corpus can
// retune Q_ACCEL (docs/features/gps_distance.md § Server recompute).
const (
	EstimatorPassSmoothed = "smoothed"
	EstimatorPassForward  = "forward"
)

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

// handleDistanceRecompute replays a stored track through the spec-v1.2
// smoother and rewrites runs.distance_m, keeping the originally
// recorded figure in metadata.distance_recorded_m, and rewrites the four
// fastest_* embedded bests from the same replay's cumulative distance.
// When it keeps the smoothed pass it also writes the smoothed-position
// sidecar (smoothed_sidecar.go), after the distance write has landed.
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

		track, err := w.Backend.DownloadRecordedTrack(ctx, *run.TrackURL)
		if err != nil {
			return fmt.Errorf("download track: %w", err)
		}
		pts, storedIdx := coordinatePointsIndexed(track.Points)
		replay := replayRecordedTrack(pts, maxSpeedMpsForActivity(run.ActivityType))
		if replay.Fixes < 2 {
			return fmt.Errorf("track %s has %d timestamped waypoints; need at least 2", *run.TrackURL, replay.Fixes)
		}
		pass, why := w.distanceEstimatorPass(ctx, run, meta, pts, replay)
		rawDistanceM, cum := replay.SmoothedM, replay.SmoothedCumM
		if pass == EstimatorPassForward {
			rawDistanceM, cum = replay.ForwardM, replay.ForwardCumM
		}
		distanceM := math.Round(rawDistanceM*100) / 100

		merged, err := mergeDistanceMetadata(meta, run.DistanceM, pass, time.Now().UTC())
		if err != nil {
			return err
		}
		err = w.Backend.UpdateRunDistance(ctx, run, RunDistanceUpdate{
			DistanceM:     distanceM,
			EmbeddedBests: embeddedBestsOver(pts, cum),
			Metadata:      merged,
		})
		if errors.Is(err, ErrRunChangedDuringRecompute) {
			w.Log.Info("run changed during distance recompute; re-reading",
				"run_id", p.RunID, "attempt", attempt)
			continue
		}
		if err != nil {
			return fmt.Errorf("update run distance: %w", err)
		}
		// The line follows the figure the run now carries: a forward-pass
		// recompute keeps its raw line rather than the smoother's, which
		// cuts the corners the forward pass was kept to avoid, and so removes
		// a sidecar an earlier smoothed-pass recompute of this same track
		// left (its fingerprint would still match).
		if pass == EstimatorPassSmoothed {
			w.writeSmoothedSidecar(ctx, run.UserID, run.ID, track, storedIdx, replay)
		} else if err := w.Backend.DeleteStorageObjects(ctx, schema.BucketRuns,
			[]string{smoothedSidecarPath(run.UserID, run.ID)}); err != nil {
			w.Log.Warn("stale smoothed sidecar not removed", "run_id", run.ID, "err", err)
		}
		w.Log.Info("distance recomputed",
			"run_id", p.RunID,
			"previous_m", run.DistanceM,
			"distance_m", distanceM,
			"fixes", replay.Fixes,
			"pass", pass,
			"pass_reason", why,
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
// estimator's to replace, or "" when it is. The clients' offer gate —
// canRecomputeDistance in apps/web/src/lib/runs/distance_recompute.ts and
// apps/mobile_android/lib/distance_recompute.dart — mirrors this rule so a
// runner is never offered a recompute this skips silently; change them
// together.
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

// mergeDistanceMetadata adds the recompute's four keys to the bag and
// leaves every other key byte-for-byte as read. distance_recorded_m keeps
// an existing value so a repeated recompute never overwrites the
// recorder's original figure with a previous recompute's.
func mergeDistanceMetadata(meta map[string]json.RawMessage, previousDistanceM float64, pass string, now time.Time) (json.RawMessage, error) {
	out := make(map[string]json.RawMessage, len(meta)+4)
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
	est, _ := json.Marshal(DistanceEstimatorV2)
	out[schema.MetaDistanceEstimator] = est
	p, _ := json.Marshal(pass)
	out[schema.MetaDistanceEstimatorPass] = p
	at, _ := json.Marshal(now.Format(time.RFC3339))
	out[schema.MetaDistanceRecomputedAt] = at
	return json.Marshal(out)
}

// distanceEstimatorPass decides which of the replay's passes the recompute
// keeps, and why. Only a position-only track can take the forward pass, and
// only when it is not a road run by the map_match step's own classifier,
// roadDistanceFor: either that step already measured this track along the
// road graph (metadata.distance_map_matched_m), or the matcher measures it
// now and the classifier accepts it, checked against the smoothed figure
// because the stored distance_m of an old run is the inflated hop-sum. A
// matcher failure is auxiliary to the distance and leaves the run unclassified,
// which keeps the forward figure.
func (w *Worker) distanceEstimatorPass(
	ctx context.Context, run *DistanceRecomputeRun, meta map[string]json.RawMessage,
	pts []RecordedTrackPoint, replay trackReplay,
) (string, string) {
	if !replay.PositionOnly {
		return EstimatorPassSmoothed, "track carries Doppler speed"
	}
	var matched float64
	if json.Unmarshal(meta[schema.MetaDistanceMapMatchedM], &matched) == nil && matched > 0 {
		return EstimatorPassSmoothed, "road run: map_match measured it on the road graph"
	}
	rm, ok := w.Matcher.(RoadDistanceMatcher)
	if !ok {
		return EstimatorPassForward, "no road matcher to classify a position-only track"
	}
	raw := make([]TrackPoint, 0, len(pts))
	for _, p := range pts {
		raw = append(raw, TrackPoint{Lat: *p.Lat, Lng: *p.Lng, Timestamp: p.Timestamp})
	}
	out, road, err := rm.MatchWithRoadDistance(ctx, raw)
	if err != nil {
		w.Log.Warn("distance recompute road match failed; keeping the forward pass", "run_id", run.ID, "err", err)
		return EstimatorPassForward, "road match failed"
	}
	if len(out) < 2 {
		road = RoadMatch{}
	}
	activity := run.ActivityType
	candidate := &RoadDistanceRun{
		ID: run.ID, ActivityType: &activity, TrackURL: run.TrackURL,
		DistanceM: replay.SmoothedM, Metadata: run.Metadata, Route: run.Route,
	}
	if v, reason := roadDistanceFor(candidate, meta, raw, road); v == nil {
		return EstimatorPassForward, "not a road run: " + reason
	}
	return EstimatorPassSmoothed, "road run: matched on the road graph"
}
