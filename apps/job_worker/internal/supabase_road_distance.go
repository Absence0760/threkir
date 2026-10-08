package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// ReadRunForRoadDistance loads the columns the road-distance step decides
// on, with the linked route's surface embedded through runs.route_id.
// Returns ErrRunNotFound for a deleted run.
func (c *SupabaseClient) ReadRunForRoadDistance(ctx context.Context, runID string) (*RoadDistanceRun, error) {
	q := url.Values{}
	q.Set("id", "eq."+runID)
	q.Set("select", "id,activity_type,track_url,distance_m,metadata,route:"+schema.TableRoutes+"(surface)")
	u := c.BaseURL + "/rest/v1/" + schema.TableRuns + "?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []RoadDistanceRun
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, fmt.Errorf("decode run: %w", err)
	}
	if len(rows) == 0 {
		return nil, ErrRunNotFound
	}
	return &rows[0], nil
}

// UpdateRunMetadata replaces the run's metadata bag with `metadata`,
// conditional on the row still holding `trackURL` and the exact bag the
// worker read (jsonb equality, so key order is irrelevant). PostgREST
// cannot merge into a jsonb column, so the caller merges over the bytes it
// read and this filter is what stops that from erasing a concurrent edit.
// Returns ErrRunMetadataChanged on a miss.
func (c *SupabaseClient) UpdateRunMetadata(ctx context.Context, read *RoadDistanceRun, trackURL string, metadata json.RawMessage) error {
	payload, err := json.Marshal(map[string]any{"metadata": metadata})
	if err != nil {
		return err
	}
	q := url.Values{}
	q.Set("id", "eq."+read.ID)
	q.Set("track_url", "eq."+trackURL)
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
		return ErrRunMetadataChanged
	}
	return nil
}
