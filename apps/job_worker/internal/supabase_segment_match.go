package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/Absence0760/threkir/apps/job_worker/internal/supakey"
)

// SegmentMatchTimeout bounds one call to the `segment-match` Edge Function.
// A backfill batch downloads and scores 20 tracks, so the shared 30 s client
// timeout is too short; this stays under the 5-minute per-job clock so a
// wedged call is reported as a transient failure rather than outliving its
// job.
const SegmentMatchTimeout = 150 * time.Second

// InvokeSegmentMatch POSTs a segment_match job's payload to the Edge
// Function with the worker's server key on `apikey` (and as the bearer for a
// legacy JWT key, internal/supakey), the key the function's own gate accepts.
// A non-2xx answer is an *HTTPError carrying the status and never the body.
func (c *SupabaseClient) InvokeSegmentMatch(ctx context.Context, payload json.RawMessage) error {
	url := strings.TrimRight(c.BaseURL, "/") + "/functions/v1/segment-match"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	supakey.SetAuthHeaders(req.Header, c.ServiceKey)

	client := &http.Client{Timeout: SegmentMatchTimeout}
	if c.HTTP != nil {
		client.Transport = c.HTTP.Transport
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return &HTTPError{
			StatusCode: resp.StatusCode,
			Method:     req.Method,
			Endpoint:   req.URL.Path,
			Body:       string(body),
		}
	}
	return nil
}
