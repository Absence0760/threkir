package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"time"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// DistanceRecomputeRun is the projection of `runs` the distance
// recompute reads. Metadata stays raw: the write merges three keys into
// it without decoding anything else, and the same bytes are the CAS
// literal that proves nobody edited the bag in between.
type DistanceRecomputeRun struct {
	ID           string          `json:"id"`
	UserID       string          `json:"user_id"`
	Source       string          `json:"source"`
	ActivityType string          `json:"activity_type"`
	TrackURL     *string         `json:"track_url"`
	DistanceM    float64         `json:"distance_m"`
	Metadata     json.RawMessage `json:"metadata"`
}

// RecordedTrackPoint is a stored waypoint as the distance recompute
// reads it: position + timestamp, plus the four optional spec-v1 keys
// (docs/features/gps_distance.md § Waypoint fields). Tracks recorded
// before v1 carry none of them and recompute through the position-only
// path. Lat/Lng are pointers so a null coordinate is skipped rather
// than read as (0, 0).
type RecordedTrackPoint struct {
	Lat              *float64   `json:"lat"`
	Lng              *float64   `json:"lng"`
	Timestamp        *time.Time `json:"ts,omitempty"`
	AccuracyM        *float64   `json:"accuracyMetres,omitempty"`
	SpeedMps         *float64   `json:"speedMps,omitempty"`
	SpeedAccuracyMps *float64   `json:"speedAccuracyMps,omitempty"`
	BearingDeg       *float64   `json:"bearingDeg,omitempty"`
}

// ErrRunNotFound means the run named by a job payload no longer exists
// (deleted between enqueue and claim). The recompute treats it as a
// no-op rather than a failure.
var ErrRunNotFound = errors.New("run not found")

// ErrRunChangedDuringRecompute is returned by UpdateRunDistance when the
// conditional PATCH matched no row: the track was re-uploaded or the
// metadata bag was edited after the worker read it.
var ErrRunChangedDuringRecompute = errors.New("run changed during distance recompute")

// ReadRunForDistanceRecompute loads the columns the recompute decides on.
func (c *SupabaseClient) ReadRunForDistanceRecompute(ctx context.Context, runID string) (*DistanceRecomputeRun, error) {
	q := url.Values{}
	q.Set("id", "eq."+runID)
	q.Set("select", "id,user_id,source,activity_type,track_url,distance_m,metadata")
	u := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []DistanceRecomputeRun
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, fmt.Errorf("decode run: %w", err)
	}
	if len(rows) == 0 {
		return nil, ErrRunNotFound
	}
	return &rows[0], nil
}

// DownloadRecordedTrack fetches a track from the `runs` bucket the same
// way DownloadTrack does, decoding the Doppler keys as well.
func (c *SupabaseClient) DownloadRecordedTrack(ctx context.Context, path string) ([]RecordedTrackPoint, error) {
	u := c.BaseURL + "/storage/v1/object/" + schema.BucketRuns + "/" + path
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	pts, err := decodeTrack[RecordedTrackPoint](body)
	if err != nil {
		return nil, fmt.Errorf("parse track %s: %w", path, err)
	}
	return pts, nil
}

// RunDistanceUpdate is what one recompute writes: the distance, every
// fastest_* column keyed by name (nil writes null), and the merged bag.
type RunDistanceUpdate struct {
	DistanceM     float64
	EmbeddedBests map[string]*int
	Metadata      json.RawMessage
}

// UpdateRunDistance writes the recomputed distance, the embedded bests and
// the merged metadata bag in one PATCH, conditional on the run still holding the track_url and
// metadata the worker read. PostgREST cannot merge into a jsonb column,
// so the merge is done by the caller over the bytes it read; the
// metadata filter (jsonb equality, so key order is irrelevant) is what
// stops that read-modify-write from erasing a concurrent edit — a title
// rename, a gear tag. Returns ErrRunChangedDuringRecompute on a miss.
func (c *SupabaseClient) UpdateRunDistance(
	ctx context.Context, read *DistanceRecomputeRun, upd RunDistanceUpdate,
) error {
	if read.TrackURL == nil {
		return errors.New("update run distance: read carries no track_url")
	}
	fields := map[string]any{
		"distance_m": upd.DistanceM,
		"metadata":   upd.Metadata,
	}
	for col, secs := range upd.EmbeddedBests {
		fields[col] = secs
	}
	payload, err := json.Marshal(fields)
	if err != nil {
		return err
	}
	q := url.Values{}
	q.Set("id", "eq."+read.ID)
	q.Set("track_url", "eq."+*read.TrackURL)
	if isJSONNull(read.Metadata) {
		q.Set("metadata", "is.null")
	} else {
		q.Set("metadata", "eq."+string(read.Metadata))
	}
	q.Set("select", "id")
	u := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, u, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	// return=representation is how the CAS is counted: with
	// return=minimal a zero-row PATCH is an indistinguishable 204.
	req.Header.Set("Prefer", "return=representation")
	body, err := c.do(ctx, req)
	if err != nil {
		return err
	}
	var rows []json.RawMessage
	if err := json.Unmarshal(body, &rows); err != nil {
		return fmt.Errorf("decode update response: %w", err)
	}
	if len(rows) == 0 {
		return ErrRunChangedDuringRecompute
	}
	return nil
}

func isJSONNull(raw json.RawMessage) bool {
	return len(bytes.TrimSpace(raw)) == 0 || string(bytes.TrimSpace(raw)) == "null"
}
