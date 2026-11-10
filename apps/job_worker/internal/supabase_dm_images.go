package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
	"github.com/Absence0760/threkir/apps/job_worker/internal/supakey"
)

// DmImage is the slice of a direct_message_images row the dm_image_process
// handler needs.
type DmImage struct {
	ID          string `json:"id"`
	Status      string `json:"status"`
	UploadPath  string `json:"upload_path"`
	StoragePath string `json:"storage_path"`
}

// ErrDmImageTooLarge is DownloadDmImage's answer for an object longer than
// the caller's cap.
var ErrDmImageTooLarge = errors.New("dm image upload over the size limit")

// dmImageStorageEndpoint is what a dm-images error reports in place of the
// object URL: `{owner}/{image}` names the sender, and an error reaches both
// the log and jobs.error.
const dmImageStorageEndpoint = "/storage/v1/object/" + schema.BucketDmImages

// redactDmImageError replaces the object path in a Storage error with the
// bucket. The status code and the transport error text survive, so
// isTransient still classifies a 5xx or a connection reset as a retry.
func (c *SupabaseClient) redactDmImageError(err error) error {
	var hErr *HTTPError
	if errors.As(err, &hErr) {
		return &HTTPError{StatusCode: hErr.StatusCode, Method: hErr.Method, Endpoint: dmImageStorageEndpoint, Body: hErr.Body}
	}
	var uErr *url.Error
	if errors.As(err, &uErr) {
		return &url.Error{Op: uErr.Op, URL: c.BaseURL + dmImageStorageEndpoint, Err: uErr.Err}
	}
	return err
}

// FetchDmImage reads one direct_message_images row through the service role.
func (c *SupabaseClient) FetchDmImage(ctx context.Context, imageID string) (*DmImage, error) {
	q := url.Values{}
	q.Set("id", "eq."+imageID)
	q.Set("select", "id,status,upload_path,storage_path")
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		c.BaseURL+"/rest/v1/"+schema.TableDirectMessageImages+"?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	body, err := c.do(ctx, req)
	if err != nil {
		return nil, err
	}
	var rows []DmImage
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return &rows[0], nil
}

// DownloadDmImage reads an object from the dm-images bucket, refusing past
// maxBytes without buffering the rest.
func (c *SupabaseClient) DownloadDmImage(ctx context.Context, path string, maxBytes int64) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		c.BaseURL+"/storage/v1/object/"+schema.BucketDmImages+"/"+path, nil)
	if err != nil {
		return nil, c.redactDmImageError(err)
	}
	supakey.SetAuthHeaders(req.Header, c.ServiceKey)
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, c.redactDmImageError(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, &HTTPError{StatusCode: resp.StatusCode, Method: http.MethodGet, Endpoint: dmImageStorageEndpoint, Body: string(msg)}
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBytes+1))
	if err != nil {
		return nil, c.redactDmImageError(err)
	}
	if int64(len(body)) > maxBytes {
		return nil, ErrDmImageTooLarge
	}
	return body, nil
}

// UploadDmImage writes the re-encoded JPEG. x-upsert lets a retried job
// overwrite what an earlier attempt wrote before it failed to mark the row.
func (c *SupabaseClient) UploadDmImage(ctx context.Context, path string, body []byte) error {
	return c.redactDmImageError(c.uploadToBucket(ctx, schema.BucketDmImages, path, body, "image/jpeg"))
}

// MarkDmImageReady records the re-encode. The status=eq.pending filter makes
// it a no-op on a row a concurrent attempt already settled; false means no
// pending row matched (settled, or deleted while the worker ran).
func (c *SupabaseClient) MarkDmImageReady(ctx context.Context, imageID string, width, height int) (bool, error) {
	return c.patchPendingDmImage(ctx, imageID, map[string]any{
		"status":       "ready",
		"width":        width,
		"height":       height,
		"processed_at": time.Now().UTC().Format(time.RFC3339Nano),
	})
}

// MarkDmImageRejected records that the upload could not be used. Filtered
// on status=eq.pending like MarkDmImageReady, so it never demotes a ready row.
func (c *SupabaseClient) MarkDmImageRejected(ctx context.Context, imageID string) (bool, error) {
	return c.patchPendingDmImage(ctx, imageID, map[string]any{
		"status":       "rejected",
		"processed_at": time.Now().UTC().Format(time.RFC3339Nano),
	})
}

func (c *SupabaseClient) patchPendingDmImage(ctx context.Context, imageID string, patch map[string]any) (bool, error) {
	payload, err := json.Marshal(patch)
	if err != nil {
		return false, err
	}
	q := url.Values{}
	q.Set("id", "eq."+imageID)
	q.Set("status", "eq.pending")
	q.Set("select", "id")
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch,
		c.BaseURL+"/rest/v1/"+schema.TableDirectMessageImages+"?"+q.Encode(), bytes.NewReader(payload))
	if err != nil {
		return false, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=representation")
	body, err := c.do(ctx, req)
	if err != nil {
		return false, err
	}
	var rows []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return false, fmt.Errorf("direct_message_images patch: decode: %w", err)
	}
	return len(rows) > 0, nil
}

// DmImageOrphanPaths calls `dm_image_orphan_paths`, the service-role worklist
// for the dm-images orphan sweep. A nil `paths` is sent as SQL NULL (the
// 24-hour-graced backstop); a non-nil one scopes the result to it.
func (c *SupabaseClient) DmImageOrphanPaths(ctx context.Context, paths []string, limit int) ([]string, error) {
	params := map[string]any{"p_paths": nil, "p_limit": limit}
	if paths != nil {
		params["p_paths"] = paths
	}
	var out []string
	if err := c.rpc(ctx, "dm_image_orphan_paths", params, &out); err != nil {
		return nil, err
	}
	return out, nil
}
