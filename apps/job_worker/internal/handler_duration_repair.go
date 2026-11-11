package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// DurationRepairPayload is what migration 20271218000002 enqueues for
// kind='duration_repair': one run it capped at the ten-day bound that has a
// stored track.
type DurationRepairPayload struct {
	RunID  string `json:"run_id"`
	UserID string `json:"user_id,omitempty"`
}

// MaxRunDurationS is runs_duration_s_max_check's bound, ten days. A stored
// duration of exactly this is the repair's placeholder, so a track span is
// written only when it is strictly under it.
const MaxRunDurationS = 864000

const durationRepairMaxAttempts = 3

// handleDurationRepair replaces a capped duration with the span of the run's
// track timestamps when that span is believable (trackDurationS). Anything
// it cannot repair keeps the cap and its flag and finishes the job: the row
// already satisfies the constraint, and only its owner can say how long a
// run with no usable track lasted.
func (w *Worker) handleDurationRepair(ctx context.Context, job *Job) error {
	var p DurationRepairPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if !reRunUUID.MatchString(p.RunID) {
		return fmt.Errorf("payload run_id %q is not a uuid", p.RunID)
	}

	for attempt := 1; attempt <= durationRepairMaxAttempts; attempt++ {
		run, err := w.Backend.ReadRunForDurationRepair(ctx, p.RunID)
		if errors.Is(err, ErrRunNotFound) {
			w.Log.Info("duration repair skipped", "run_id", p.RunID, "reason", "run no longer exists")
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
		if !metaIsTrue(meta, schema.MetaDurationRepaired) {
			w.Log.Info("duration repair skipped", "run_id", p.RunID, "reason", "no longer flagged")
			return nil
		}
		if run.TrackURL == nil || *run.TrackURL == "" {
			w.Log.Info("duration repair kept the cap", "run_id", p.RunID, "reason", "no track")
			return nil
		}

		track, err := w.Backend.DownloadRecordedTrack(ctx, *run.TrackURL)
		var hErr *HTTPError
		if errors.As(err, &hErr) && (hErr.StatusCode == http.StatusNotFound || hErr.StatusCode == http.StatusBadRequest) {
			// Storage answers a missing object with 400 or 404.
			w.Log.Info("duration repair kept the cap", "run_id", p.RunID, "reason", "track object missing")
			return nil
		}
		if err != nil {
			return fmt.Errorf("download track: %w", err)
		}
		secs, why := trackDurationS(track.Points, run.DistanceM, maxSpeedMpsForActivity(run.ActivityType))
		if secs == 0 {
			w.Log.Info("duration repair kept the cap", "run_id", p.RunID, "reason", why)
			return nil
		}

		err = w.Backend.UpdateRunDuration(ctx, run, secs)
		if errors.Is(err, ErrRunChangedDuringDurationRepair) {
			w.Log.Info("run changed during duration repair; re-reading", "run_id", p.RunID, "attempt", attempt)
			continue
		}
		if err != nil {
			return fmt.Errorf("update run duration: %w", err)
		}
		w.Log.Info("duration repaired from track", "run_id", p.RunID, "duration_s", secs)
		return nil
	}
	return fmt.Errorf("run %s changed on each of %d attempts; not repaired", p.RunID, durationRepairMaxAttempts)
}

// trackDurationS is the span from the earliest to the latest timestamped
// waypoint, in whole seconds, or 0 and the reason it is not usable. It is the
// run's elapsed time, so it can only be at or above a recorder's
// pause-excluding duration, never below; a stored track has no pause marks to
// do better. It is refused when it is not positive, is not under the bound,
// or would put the run's average speed above its activity's ceiling — a
// track that covers only part of the run, or a clock that stood still, would
// otherwise hand the run a pace it never ran, and a PR with it.
func trackDurationS(pts []RecordedTrackPoint, distanceM, maxSpeedMps float64) (int, string) {
	var first, last time.Time
	n := 0
	for _, p := range pts {
		if p.Timestamp == nil || p.Timestamp.IsZero() {
			continue
		}
		t := *p.Timestamp
		if n == 0 || t.Before(first) {
			first = t
		}
		if n == 0 || t.After(last) {
			last = t
		}
		n++
	}
	if n < 2 {
		return 0, "track has fewer than 2 timestamped waypoints"
	}
	secs := int(last.Sub(first) / time.Second)
	switch {
	case secs <= 0:
		return 0, "track timestamps span no time"
	case secs >= MaxRunDurationS:
		return 0, "track timestamps span ten days or more"
	case distanceM/float64(secs) > maxSpeedMps:
		return 0, "track span is too short for the run's distance"
	}
	return secs, ""
}
