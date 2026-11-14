package internal

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// HealthDataConsented asks `health_data_consented`, the service-role RPC the
// heart-rate gates share (migration 20271227100001, decisions § 2514).
func (c *SupabaseClient) HealthDataConsented(ctx context.Context, userID string) (bool, error) {
	var out bool
	if err := c.rpc(ctx, "health_data_consented", map[string]any{"p_user_id": userID}, &out); err != nil {
		return false, err
	}
	return out, nil
}

// ListRunsForHealthErase pages a runner's runs in id order after `afterID`,
// reading only the heart-rate keys of the metadata bag.
func (c *SupabaseClient) ListRunsForHealthErase(ctx context.Context, userID, afterID string, limit int) ([]HealthEraseRun, error) {
	q := url.Values{}
	q.Set("select", "id,track_url,hr_series_url,avg_bpm:metadata->avg_bpm,max_bpm:metadata->max_bpm,hr_coverage:metadata->hr_coverage")
	q.Set("user_id", "eq."+userID)
	q.Set("order", "id.asc")
	q.Set("limit", fmt.Sprint(limit))
	if afterID != "" {
		q.Set("id", "gt."+afterID)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		c.BaseURL+"/rest/v1/runs?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []struct {
		HealthEraseRun
		AvgBpm     json.RawMessage `json:"avg_bpm"`
		MaxBpm     json.RawMessage `json:"max_bpm"`
		HRCoverage json.RawMessage `json:"hr_coverage"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, fmt.Errorf("decode runs: %w", err)
	}
	out := make([]HealthEraseRun, len(rows))
	for i, r := range rows {
		run := r.HealthEraseRun
		run.HasHR = jsonPresent(r.AvgBpm) || jsonPresent(r.MaxBpm) || jsonPresent(r.HRCoverage) ||
			(run.HRSeriesURL != nil && *run.HRSeriesURL != "")
		out[i] = run
	}
	return out, nil
}

func jsonPresent(v json.RawMessage) bool {
	return len(v) > 0 && string(v) != "null"
}

// DownloadRunsObject reads one object from the runs bucket as stored.
func (c *SupabaseClient) DownloadRunsObject(ctx context.Context, path string) ([]byte, error) {
	body, _, err := c.downloadFromBucket(ctx, schema.BucketRuns, path)
	return body, err
}

// UploadRunsObject overwrites one object in the runs bucket.
func (c *SupabaseClient) UploadRunsObject(ctx context.Context, path string, body []byte, contentType string) error {
	return c.uploadToBucket(ctx, schema.BucketRuns, path, body, contentType)
}
