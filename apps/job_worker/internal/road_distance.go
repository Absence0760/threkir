package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// RoadMatch is what a road-aware matcher reports beside the matched
// track. DistanceM is nil whenever any stretch of the run was not
// attributed to the road graph, so a figure is either the whole run or
// absent.
type RoadMatch struct {
	DistanceM     *float64
	MinConfidence float64
}

// RoadDistanceMatcher is a Matcher that can also measure the matched track
// along the road graph. The worker uses it when the configured matcher
// implements it; PassthroughMatcher does not, so it never produces a road
// distance.
type RoadDistanceMatcher interface {
	Matcher
	MatchWithRoadDistance(ctx context.Context, points []TrackPoint) ([]TrackPoint, RoadMatch, error)
}

// The thresholds a road distance must clear. None is validated against
// real tracks yet: they are deliberately conservative, because a wrong
// figure shown beside the run is worse than none, and they are for the
// GPS ground-truth corpus (fixtures/gps_corpus/) to tune.
const (
	// roadMinConfidence is the lowest OSRM matching confidence (0..1) any
	// chunk may carry.
	roadMinConfidence = 0.5
	// roadMaxRelDiff bounds how far the road figure may sit from
	// distance_m. A larger gap is a snap onto the wrong street or a detour
	// through the graph, not a correction of GPS noise.
	roadMaxRelDiff = 0.15
	// roadMinFootprintM is the smallest bounding-box diagonal a road run
	// covers. A running track (a 400 m oval spans ~200 m) or laps of a
	// car park fit inside it, and the foot graph has no lane-1 line to
	// measure them on.
	roadMinFootprintM = 300.0
)

// roadSubSports are the FIT sub_sport values that say a run was on a road.
// Any other recorded discipline (trail, track, treadmill, indoor, ...) rules
// the run out; an absent one leaves the decision to the other checks.
var roadSubSports = map[string]bool{"road": true, "street": true}

// roadStravaTypes are the Strava activity types that may be on a road; a
// TrailRun, Hike or VirtualRun is not.
var roadStravaTypes = map[string]bool{"Run": true, "Walk": true}

// roadActivityTypes are the foot activities the foot graph models. A hike
// is trail by nature and a ride is not on the foot graph.
var roadActivityTypes = map[string]bool{"": true, "run": true, "walk": true, "stroller": true}

// RoadDistanceRun is the projection of `runs` the road-distance step reads,
// and the watch-run smoothed-sidecar step after it (UserID, Source).
// Route is the linked route's surface through the runs.route_id foreign
// key, nil when no route is linked.
type RoadDistanceRun struct {
	ID           string            `json:"id"`
	UserID       string            `json:"user_id"`
	Source       string            `json:"source"`
	ActivityType *string           `json:"activity_type"`
	TrackURL     *string           `json:"track_url"`
	DistanceM    float64           `json:"distance_m"`
	Metadata     json.RawMessage   `json:"metadata"`
	Route        *RoadRouteSurface `json:"route"`
}

// RoadRouteSurface is a run's linked route as the road classifier reads it.
type RoadRouteSurface struct {
	Surface *string `json:"surface"`
}

// ErrRunMetadataChanged is returned by UpdateRunMetadata when its
// conditional PATCH matched no row: the track was re-uploaded or the
// metadata bag was edited after the worker read it.
var ErrRunMetadataChanged = errors.New("run metadata changed under the worker")

const roadDistanceMaxAttempts = 3

// roadDistanceFor decides the value of distance_map_matched_m for one run:
// the matched road length in metres (rounded to 0.1 m), or nil with the
// reason it does not apply. A nil value clears a stale key a previous
// track left behind.
func roadDistanceFor(run *RoadDistanceRun, meta map[string]json.RawMessage, raw []TrackPoint, road RoadMatch) (*float64, string) {
	activity := ""
	if run.ActivityType != nil {
		activity = *run.ActivityType
	}
	if !roadActivityTypes[activity] {
		return nil, "activity " + activity + " is not on the foot road graph"
	}
	if metaIsTrue(meta, schema.MetaIndoor) || metaIsTrue(meta, schema.MetaIndoorEstimated) {
		return nil, "indoor run"
	}
	if sub := metaString(meta, schema.MetaSubSport); sub != "" && !roadSubSports[sub] {
		return nil, "sub_sport " + sub + " is not a road discipline"
	}
	if st := metaString(meta, schema.MetaStravaActivityType); st != "" && !roadStravaTypes[st] {
		return nil, "strava activity type " + st + " is not a road discipline"
	}
	if run.Route != nil && run.Route.Surface != nil && *run.Route.Surface != "road" {
		return nil, "linked route surface is " + *run.Route.Surface
	}
	if footprintM(raw) < roadMinFootprintM {
		return nil, "track-sized footprint"
	}
	if road.DistanceM == nil {
		return nil, "part of the run was not matched to the road graph"
	}
	if road.MinConfidence < roadMinConfidence {
		return nil, fmt.Sprintf("matcher confidence %.2f below %.2f", road.MinConfidence, roadMinConfidence)
	}
	if !(run.DistanceM > 0) {
		return nil, "no recorded distance to check against"
	}
	if math.Abs(*road.DistanceM-run.DistanceM)/run.DistanceM > roadMaxRelDiff {
		return nil, "road distance disagrees with the recorded distance"
	}
	v := math.Round(*road.DistanceM*10) / 10
	return &v, ""
}

// mergeRoadDistance returns meta with distance_map_matched_m set to want
// and distance_map_matched_track_version to version, or both removed when
// want is nil, and whether that changes the stored bag. The pair travels
// together: the runs_road_distance_matches_track trigger keeps a figure
// only while its version names the bytes now behind track_url.
func mergeRoadDistance(meta map[string]json.RawMessage, want *float64, version string) (json.RawMessage, bool, error) {
	oldM, hadM := meta[schema.MetaDistanceMapMatchedM]
	oldV, hadV := meta[schema.MetaDistanceMapMatchedTrackVersion]
	out := make(map[string]json.RawMessage, len(meta)+2)
	for k, v := range meta {
		out[k] = v
	}
	if want == nil {
		if !hadM && !hadV {
			return nil, false, nil
		}
		delete(out, schema.MetaDistanceMapMatchedM)
		delete(out, schema.MetaDistanceMapMatchedTrackVersion)
	} else {
		encM, err := json.Marshal(*want)
		if err != nil {
			return nil, false, err
		}
		encV, err := json.Marshal(version)
		if err != nil {
			return nil, false, err
		}
		if hadM && hadV {
			var cur float64
			var curV string
			if json.Unmarshal(oldM, &cur) == nil && cur == *want &&
				json.Unmarshal(oldV, &curV) == nil && curV == version {
				return nil, false, nil
			}
		}
		out[schema.MetaDistanceMapMatchedM] = encM
		out[schema.MetaDistanceMapMatchedTrackVersion] = encV
	}
	merged, err := json.Marshal(out)
	if err != nil {
		return nil, false, err
	}
	return merged, true, nil
}

// updateRoadDistance writes (or clears) metadata.distance_map_matched_m for
// the run the map_match job just matched against src. The write is a
// read-modify-write of the whole bag, conditional on the bag and the
// track_url the worker read, so it cannot erase a concurrent edit; on a
// miss it re-reads. It stamps the figure with src.Version, and the
// runs_road_distance_matches_track trigger (20270719000020) drops a figure
// whose version is not the stored object's, so a track re-uploaded in place
// while this job ran cannot be left with the old bytes' road distance. It
// never touches distance_m or a fastest_* column, and it carries the bag it
// read — distance_recomputed_at included — so the runs_keep_distance_recompute
// trigger (20270719000003) sees a current write and leaves it alone.
func (w *Worker) updateRoadDistance(ctx context.Context, runID string, src TrackSource, raw []TrackPoint, road RoadMatch) error {
	trackURL := src.URL
	for attempt := 1; attempt <= roadDistanceMaxAttempts; attempt++ {
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
		want, reason := roadDistanceFor(run, meta, raw, road)
		merged, changed, err := mergeRoadDistance(meta, want, src.Version)
		if err != nil {
			return err
		}
		if !changed {
			return nil
		}
		err = w.Backend.UpdateRunMetadata(ctx, run, trackURL, merged)
		if errors.Is(err, ErrRunMetadataChanged) {
			continue
		}
		if err != nil {
			return fmt.Errorf("update run metadata: %w", err)
		}
		if want != nil {
			w.Log.Info("road distance stored", "run_id", runID, "distance_map_matched_m", *want, "distance_m", run.DistanceM)
		} else {
			w.Log.Info("road distance cleared", "run_id", runID, "reason", reason)
		}
		return nil
	}
	return fmt.Errorf("run %s changed on each of %d attempts; road distance not written", runID, roadDistanceMaxAttempts)
}

// footprintM is the diagonal of the track's bounding box in metres.
func footprintM(pts []TrackPoint) float64 {
	if len(pts) == 0 {
		return 0
	}
	minLat, maxLat, minLng, maxLng := pts[0].Lat, pts[0].Lat, pts[0].Lng, pts[0].Lng
	for _, p := range pts[1:] {
		minLat, maxLat = math.Min(minLat, p.Lat), math.Max(maxLat, p.Lat)
		minLng, maxLng = math.Min(minLng, p.Lng), math.Max(maxLng, p.Lng)
	}
	return haversineM(TrackPoint{Lat: minLat, Lng: minLng}, TrackPoint{Lat: maxLat, Lng: maxLng})
}

// haversineM is the great-circle distance between two points in metres.
func haversineM(a, b TrackPoint) float64 {
	rad := func(d float64) float64 { return d * math.Pi / 180 }
	lat1, lat2 := rad(a.Lat), rad(b.Lat)
	dLat, dLng := lat2-lat1, rad(b.Lng-a.Lng)
	h := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(lat1)*math.Cos(lat2)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * 6371000 * math.Asin(math.Min(1, math.Sqrt(h)))
}

// writeWatchSmoothedSidecar is the map_match job's last step: for a run the
// wrist recorded (source 'watch', whose recorders keep the forward filter and
// never store a smoothed pair), replay the stored track through the smoother
// and write the smoothed-position sidecar. A track with no Doppler that is
// not a road run by roadDistanceFor gets none, the same rule that keeps the
// recompute on the forward pass there. road is the match this job just made.
// Auxiliary like the road distance: the caller logs an error, never fails.
func (w *Worker) writeWatchSmoothedSidecar(ctx context.Context, runID, trackURL string, road RoadMatch) error {
	run, err := w.Backend.ReadRunForRoadDistance(ctx, runID)
	if errors.Is(err, ErrRunNotFound) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read run: %w", err)
	}
	if run.Source != "watch" || run.TrackURL == nil || *run.TrackURL != trackURL {
		return nil
	}
	meta, err := decodeRunMetadata(run.Metadata)
	if err != nil {
		return fmt.Errorf("run %s metadata: %w", runID, err)
	}
	if metaIsTrue(meta, schema.MetaInProgress) {
		return nil
	}
	track, err := w.Backend.DownloadRecordedTrack(ctx, trackURL)
	if err != nil {
		return fmt.Errorf("download track: %w", err)
	}
	pts, storedIdx := coordinatePointsIndexed(track.Points)
	activity := ""
	if run.ActivityType != nil {
		activity = *run.ActivityType
	}
	replay := replayRecordedTrack(pts, maxSpeedMpsForActivity(activity))
	if replay.Fixes < 2 {
		return nil
	}
	if replay.PositionOnly {
		raw := make([]TrackPoint, 0, len(pts))
		for _, p := range pts {
			raw = append(raw, TrackPoint{Lat: *p.Lat, Lng: *p.Lng, Timestamp: p.Timestamp})
		}
		if v, reason := roadDistanceFor(run, meta, raw, road); v == nil {
			w.Log.Info("smoothed sidecar skipped", "run_id", runID, "reason", "position-only and not a road run: "+reason)
			return nil
		}
	}
	w.writeSmoothedSidecar(ctx, run.UserID, run.ID, track, storedIdx, replay)
	return nil
}
