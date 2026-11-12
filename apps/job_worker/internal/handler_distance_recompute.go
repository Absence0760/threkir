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

// DistanceEstimatorCurrent is the value stamped in
// metadata.distance_estimator: the spec-v1.4 smoother. "kalman_v3" was the
// spec-v1.3 smoother, "kalman_v2" the spec-v1.2 one and "kalman_v1" the v1 /
// v1.1 forward filter; a run recomputed under any of them is eligible again (the skip below looks only at
// whether a recompute has ever stamped the run, not at which estimator).
const DistanceEstimatorCurrent = "kalman_v4"

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

// handleDistanceRecompute replays a stored track through the smoother,
// segment by segment where a watch marked them, and rewrites
// runs.distance_m, keeping the originally recorded figure in
// metadata.distance_recorded_m, and rewrites the four fastest_* embedded
// bests from the same replay's cumulative distance.
// When it keeps the smoothed pass it also writes the smoothed-position
// sidecar (smoothed_sidecar.go) and records its hash in the same write.
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
		pass, why, err := w.distanceEstimatorPass(ctx, run, meta, pts, replay)
		if err != nil {
			return fmt.Errorf("classify road run: %w", err)
		}
		rawDistanceM, cum := replay.SmoothedM, replay.SmoothedCumM
		if pass == EstimatorPassForward {
			rawDistanceM, cum = replay.ForwardM, replay.ForwardCumM
		}
		topUpM, gapRule := gapStepCreditM(meta, replay.GapM, replay.Segments)
		switch gapRule {
		case gapRuleRejected:
			w.Log.Warn("distance recompute ignored an unusable distance_step_over_chord_m; keeping the run-total rule",
				"run_id", run.ID)
		case gapRuleSegmentsMismatch:
			w.Log.Warn("distance recompute found a different segment count from the watch's; keeping the run-total rule",
				"run_id", run.ID, "replayed_segments", replay.Segments)
		}
		rawDistanceM += topUpM
		distanceM := math.Round(rawDistanceM*100) / 100

		// The line follows the figure the run now carries, so only a
		// smoothed-pass recompute has a sidecar: a forward-pass one keeps its
		// raw line rather than the smoother's, which cuts the corners the
		// forward pass was kept to avoid. The sidecar goes up before the
		// distance write and its hash lands in that same conditional write,
		// so the run names it exactly when the figure it belongs to lands; a
		// write that never lands leaves an object nothing names.
		sidecarSHA := ""
		if pass == EstimatorPassSmoothed {
			sidecarSHA = w.uploadSmoothedSidecar(ctx, run.UserID, run.ID, track, storedIdx, replay)
		}
		merged, err := mergeDistanceMetadata(meta, run.DistanceM, pass, sidecarSHA, time.Now().UTC())
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
		// A forward-pass recompute also removes a sidecar an earlier
		// smoothed-pass recompute of this same track left (its fingerprint
		// would still match); the write above already dropped the key that
		// named it, so a refused delete leaves an object no reader fetches.
		if pass != EstimatorPassSmoothed {
			if err := w.Backend.DeleteStorageObjects(ctx, schema.BucketRuns,
				[]string{smoothedSidecarPath(run.UserID, run.ID)}); err != nil {
				w.Log.Warn("stale smoothed sidecar not removed", "run_id", run.ID, "err", err)
			}
		}
		w.Log.Info("distance recomputed",
			"run_id", p.RunID,
			"previous_m", run.DistanceM,
			"distance_m", distanceM,
			"fixes", replay.Fixes,
			"pass", pass,
			"pass_reason", why,
			"gap_rule", gapRule,
			"smoothed_sidecar", sidecarSHA != "",
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

// metaStepFilledM is metadata.distance_step_filled_m when it is a finite
// positive number, else 0.
func metaStepFilledM(meta map[string]json.RawMessage) float64 {
	var v float64
	if json.Unmarshal(meta[schema.MetaDistanceStepFilledM], &v) != nil || math.IsNaN(v) || math.IsInf(v, 0) || v <= 0 {
		return 0
	}
	return v
}

// gapStepTopUpM is the run-total rule for a run with no usable
// distance_step_over_chord_m (gapStepCreditM). The recorder credited each gap
// max(chord lower bound, steps x stride) (spec v1.4 item 9); the replay has
// no steps, so it credited each gap its chord lower bound, gapM in total,
// and the recorder's steps arrive only as the run total stepFilledM. The
// pair is credited max(gapM, stepFilledM): exact whenever every gap's
// steps fall on the same side of its chord (one gap, or a run whose stride
// is honest), and short, never long, otherwise. Adding stepFilledM on top
// would count each gap twice. The bests stay on the replay's cumulative,
// which holds the chords only and so can only make them slower.
func gapStepTopUpM(gapM, stepFilledM float64) float64 {
	return math.Max(gapM, stepFilledM) - gapM
}

// stepOverChordSlackM is how far distance_step_over_chord_m may sit above
// distance_step_filled_m and still be read: the two are summed separately
// across a watch's segments, so they can differ in the last bits, but a value
// a centimetre over is not a figure the recorder produced.
const stepOverChordSlackM = 0.01

// The ways gapStepCreditM can credit the gaps, logged with the recompute.
const (
	gapRuleStepOverChord = "step_over_chord"
	gapRuleRunTotal      = "run_total"
	gapRuleRejected      = "run_total_bad_step_over_chord"
	// The key was usable but the run-total rule credited more.
	gapRuleRunTotalOverKey = "run_total_over_step_over_chord"
	// The key was usable but no usable distance_segments sat beside it.
	gapRuleSegmentsUnknown = "run_total_no_segment_count"
	// The key was usable but the replay found a different number of
	// segments from distance_segments: the track lost its marks.
	gapRuleSegmentsMismatch = "run_total_segment_count_mismatch"
)

// gapStepCreditM is what the recompute adds to a replayed pass for the
// pedometer's share of the run's GPS gaps, and which rule gave it.
// replayedSegments is trackReplay.Segments. A watch from spec v1.7 on saves
// distance_step_over_chord_m, the steps' credit over each gap's chord summed,
// which is what the stepless replay lacks. It is read only when it is a finite
// number from 0 to distance_step_filled_m (stepOverChordSlackM over), since it
// is a part of those metres; anything else, and a run saved before the key,
// falls back to the run-total rule, gapStepTopUpM.
//
// From spec v1.8 the watch banks the steps a close commits past a segment's
// last fix whole, which is right only on a replay that ends the segment there
// too: a track that lost its segmentStart marks (an older phone re-encoding
// it on the way to storage) replays as one stream, credits that gap's chord as
// well, and the key would count it twice (285.52 m against the recorder's
// 238.00 m). So the key is read only when distance_segments, the segments the
// watch stored, equals the segments the replay found; when it is absent (a
// v1.7 watch, whose key held those steps back, is indistinguishable from a
// v1.8 run whose phone dropped the count) or differs, the run-total rule
// stands, which is short and never long. A matched key is credited as the
// larger of the two: on a marked track the replay's gaps are the recorder's,
// so the key is exact and never below the run-total rule.
func gapStepCreditM(meta map[string]json.RawMessage, gapM float64, replayedSegments int) (float64, string) {
	stepFilledM := metaStepFilledM(meta)
	runTotal := gapStepTopUpM(gapM, stepFilledM)
	raw, present := meta[schema.MetaDistanceStepOverChordM]
	if !present || isJSONNull(raw) {
		return runTotal, gapRuleRunTotal
	}
	var v float64
	if json.Unmarshal(raw, &v) != nil || math.IsNaN(v) || math.IsInf(v, 0) || v < 0 || v > stepFilledM+stepOverChordSlackM {
		return runTotal, gapRuleRejected
	}
	saved, ok := metaSegmentCount(meta)
	if !ok {
		return runTotal, gapRuleSegmentsUnknown
	}
	if saved != replayedSegments {
		return runTotal, gapRuleSegmentsMismatch
	}
	if v = math.Min(v, stepFilledM); v >= runTotal {
		return v, gapRuleStepOverChord
	}
	return runTotal, gapRuleRunTotalOverKey
}

// metaSegmentCount is metadata.distance_segments when it is a whole number of
// 1 or more.
func metaSegmentCount(meta map[string]json.RawMessage) (int, bool) {
	var v float64
	if json.Unmarshal(meta[schema.MetaDistanceSegments], &v) != nil || v < 1 || v != math.Trunc(v) || v > math.MaxInt32 {
		return 0, false
	}
	return int(v), true
}

func metaString(meta map[string]json.RawMessage, key string) string {
	var s string
	if json.Unmarshal(meta[key], &s) != nil {
		return ""
	}
	return s
}

// onTrackRaw is the line of a replayed track for the road matcher and the
// road classifier: the raw position of every coordinate-bearing point that
// is not off-track. An off-track fix is one the recorder's estimator took
// and its track gate refused (spec v1.4 canopy fixes stated 30-50 m on a
// watch), so it belongs to the distance replay and to nothing that matches
// the line to a road or a route.
func onTrackRaw(pts []RecordedTrackPoint) []TrackPoint {
	raw := make([]TrackPoint, 0, len(pts))
	for _, p := range pts {
		if p.OffTrack {
			continue
		}
		raw = append(raw, TrackPoint{Lat: *p.Lat, Lng: *p.Lng, Timestamp: p.Timestamp})
	}
	return raw
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
	case meta[schema.MetaDistanceEstimator] != nil && meta[schema.MetaDistanceRecomputedAt] == nil &&
		run.Source != "watch":
		// Stamped by the phone recorder, which saved the smoother's figure
		// over every fix; its stored track is movement-gated, so a replay
		// would see fewer fixes than the save did. The Wear OS and watchOS
		// recorders store every fix their forward filter took, so a watch
		// run's track replays whole and gains the smoother.
		return "recorded live by " + metaString(meta, schema.MetaDistanceEstimator)
	case meta[schema.MetaDistanceEstimator] != nil && meta[schema.MetaDistanceRecomputedAt] == nil &&
		trackGatedEstimators[metaString(meta, schema.MetaDistanceEstimator)] &&
		!metaIsTrue(meta, schema.MetaTrackComplete):
		// A recorder from spec v1.4 on feeds its estimator fixes up to
		// 50 m but, unless it says track_complete, stored only those
		// within its track gate, so the replay would see each canopy
		// stretch as a gap and credit only its chord.
		return "track omits fixes " + metaString(meta, schema.MetaDistanceEstimator) + " took"
	}
	return ""
}

// trackGatedEstimators are the live stamps of recorders that feed their
// estimator fixes their track gate refuses (spec v1.4 on), so their stored
// track is complete only when the run says track_complete. A spec bump adds
// its value. Recorders before v1.4 gated the estimator and the track at one
// accuracy, and the Wear OS and watchOS builds stamp their forward filter
// "kalman_v1" whatever the spec, so those stamps are judged as complete.
var trackGatedEstimators = map[string]bool{"kalman_v4": true}

// mergeDistanceMetadata adds the recompute's four keys to the bag, sets
// smoothed_sidecar_sha256 to sidecarSHA (removing it when that is ""), and
// leaves every other key byte-for-byte as read. distance_recorded_m keeps
// an existing value so a repeated recompute never overwrites the
// recorder's original figure with a previous recompute's.
func mergeDistanceMetadata(meta map[string]json.RawMessage, previousDistanceM float64, pass, sidecarSHA string, now time.Time) (json.RawMessage, error) {
	out := withSmoothedSidecarKey(meta, sidecarSHA)
	if v, ok := out[schema.MetaDistanceRecordedM]; !ok || isJSONNull(v) {
		raw, err := json.Marshal(previousDistanceM)
		if err != nil {
			return nil, err
		}
		out[schema.MetaDistanceRecordedM] = raw
	}
	est, _ := json.Marshal(DistanceEstimatorCurrent)
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
// because the stored distance_m of an old run is the inflated hop-sum.
//
// A transient matcher failure (an engine 5xx, a timeout) is returned, so the
// job is deferred and retried rather than stamping the run kalman_v4 with a
// figure its classification never decided: a stamped run is no longer offered
// Recalculate, so an outage would have pinned every road run it touched to the
// forward pass for good. Only a non-transient matcher verdict keeps the
// forward figure, as an unclassifiable run.
func (w *Worker) distanceEstimatorPass(
	ctx context.Context, run *DistanceRecomputeRun, meta map[string]json.RawMessage,
	pts []RecordedTrackPoint, replay trackReplay,
) (string, string, error) {
	if !replay.PositionOnly {
		return EstimatorPassSmoothed, "track carries Doppler speed", nil
	}
	var matched float64
	if json.Unmarshal(meta[schema.MetaDistanceMapMatchedM], &matched) == nil && matched > 0 {
		return EstimatorPassSmoothed, "road run: map_match measured it on the road graph", nil
	}
	rm, ok := w.Matcher.(RoadDistanceMatcher)
	if !ok {
		return EstimatorPassForward, "no road matcher to classify a position-only track", nil
	}
	raw := onTrackRaw(pts)
	out, road, err := rm.MatchWithRoadDistance(ctx, raw)
	if err != nil {
		if isTransient(err) {
			return "", "", err
		}
		w.Log.Warn("distance recompute road match refused; keeping the forward pass", "run_id", run.ID, "err", err)
		return EstimatorPassForward, "road match failed", nil
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
		return EstimatorPassForward, "not a road run: " + reason, nil
	}
	return EstimatorPassSmoothed, "road run: matched on the road graph", nil
}
