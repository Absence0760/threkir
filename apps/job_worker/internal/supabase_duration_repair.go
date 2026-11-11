package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// DurationRepairRun is the projection of `runs` the duration repair reads.
type DurationRepairRun struct {
	ID           string          `json:"id"`
	UserID       string          `json:"user_id"`
	ActivityType string          `json:"activity_type"`
	TrackURL     *string         `json:"track_url"`
	DistanceM    float64         `json:"distance_m"`
	DurationS    int             `json:"duration_s"`
	Metadata     json.RawMessage `json:"metadata"`
}

// ErrRunChangedDuringDurationRepair is returned by UpdateRunDuration when the
// conditional PATCH matched no row: the duration, the track or the flag
// changed after the worker read the run.
var ErrRunChangedDuringDurationRepair = errors.New("run changed during duration repair")

// ReadRunForDurationRepair loads the columns the duration repair decides on.
func (c *SupabaseClient) ReadRunForDurationRepair(ctx context.Context, runID string) (*DurationRepairRun, error) {
	q := url.Values{}
	q.Set("id", "eq."+runID)
	q.Set("select", "id,user_id,activity_type,track_url,distance_m,duration_s,metadata")
	u := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []DurationRepairRun
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, fmt.Errorf("decode run: %w", err)
	}
	if len(rows) == 0 {
		return nil, ErrRunNotFound
	}
	return &rows[0], nil
}

// UpdateRunDuration writes durationS over the cap, conditional on the run
// still holding the duration and track the worker read and still being
// flagged. It writes only duration_s: the runs_keep_duration_repair trigger
// drops metadata.duration_repaired on that write, so the bag is never
// read-modify-written here. Returns ErrRunChangedDuringDurationRepair on a
// miss.
func (c *SupabaseClient) UpdateRunDuration(ctx context.Context, read *DurationRepairRun, durationS int) error {
	if read.TrackURL == nil {
		return errors.New("update run duration: read carries no track_url")
	}
	payload, err := json.Marshal(map[string]any{"duration_s": durationS})
	if err != nil {
		return err
	}
	q := url.Values{}
	q.Set("id", "eq."+read.ID)
	q.Set("duration_s", "eq."+strconv.Itoa(read.DurationS))
	q.Set("track_url", "eq."+*read.TrackURL)
	q.Set("metadata->>"+schema.MetaDurationRepaired, "eq.true")
	q.Set("select", "id")
	u := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, u, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	// return=representation is how the CAS is counted: with return=minimal
	// a zero-row PATCH is an indistinguishable 204.
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
		return ErrRunChangedDuringDurationRepair
	}
	return nil
}
