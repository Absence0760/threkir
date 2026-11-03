package livehub

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"

	"github.com/Absence0760/threkir/apps/job_worker/internal/supakey"
)

// RunMeta captures the two `runs` columns the authorizer cares about:
// the row owner (must match the JWT's `sub` to authorise a push or a
// private spectator subscribe) and the public flag (anon spectators
// are allowed when set).
type RunMeta struct {
	UserID   string
	IsPublic bool
}

// RunMetaFetcher resolves [RunMeta] for a run id. Returns
// (nil, nil) when the row doesn't exist — the authorizer treats that
// as deny rather than allow.
//
// Tests stub this with a fake; production wires
// [SupabaseRunMetaFetcher].
type RunMetaFetcher interface {
	RunMeta(ctx context.Context, runID string) (*RunMeta, error)
}

// HeartRateConsentFetcher answers `live_heart_rate_shared(user_id)`: the
// live_overlay gate is open and the owner has health-data consent on
// record (decisions § 2265). It is deliberately not part of [RunMeta],
// whose per-room cache lives for CacheRefreshTTL: consent is withdrawn
// mid-run, and the hub must stop fanning out bpm about as fast as the
// database stops storing it.
type HeartRateConsentFetcher interface {
	HeartRateShared(ctx context.Context, userID string) (bool, error)
}

// SupabaseRunMetaFetcher reads a single `runs` row via PostgREST.
// Auths with the service-role key, same as the rest of the worker —
// the row is otherwise hidden by RLS for the hub's anon context.
type SupabaseRunMetaFetcher struct {
	BaseURL    string
	ServiceKey string
	HTTP       *http.Client
}

// RunMeta implements [RunMetaFetcher].
func (f *SupabaseRunMetaFetcher) RunMeta(ctx context.Context, runID string) (*RunMeta, error) {
	q := url.Values{}
	q.Set("id", "eq."+runID)
	q.Set("select", "user_id,is_public")
	q.Set("limit", "1")
	body, err := f.get(ctx, "/rest/v1/"+schema.TableRuns+"?"+q.Encode())
	if err != nil {
		return nil, fmt.Errorf("runmeta: fetch run: %w", err)
	}
	var rows []struct {
		UserID   string `json:"user_id"`
		IsPublic bool   `json:"is_public"`
	}
	if err := json.Unmarshal(body, &rows); err != nil {
		return nil, fmt.Errorf("runmeta: decode: %w", err)
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return &RunMeta{UserID: rows[0].UserID, IsPublic: rows[0].IsPublic}, nil
}

// HeartRateShared implements [HeartRateConsentFetcher].
func (f *SupabaseRunMetaFetcher) HeartRateShared(ctx context.Context, userID string) (bool, error) {
	payload, err := json.Marshal(map[string]string{"p_user_id": userID})
	if err != nil {
		return false, err
	}
	body, err := f.do(ctx, http.MethodPost, "/rest/v1/rpc/live_heart_rate_shared", payload)
	if err != nil {
		return false, err
	}
	var shared bool
	if err := json.Unmarshal(body, &shared); err != nil {
		return false, fmt.Errorf("runmeta: decode heart-rate consent: %w", err)
	}
	return shared, nil
}

func (f *SupabaseRunMetaFetcher) get(ctx context.Context, path string) ([]byte, error) {
	return f.do(ctx, http.MethodGet, path, nil)
}

func (f *SupabaseRunMetaFetcher) do(ctx context.Context, method, path string, payload []byte) ([]byte, error) {
	base := strings.TrimRight(f.BaseURL, "/")
	var reqBody io.Reader
	if payload != nil {
		reqBody = bytes.NewReader(payload)
	}
	req, err := http.NewRequestWithContext(ctx, method, base+path, reqBody)
	if err != nil {
		return nil, err
	}
	supakey.SetAuthHeaders(req.Header, f.ServiceKey)
	req.Header.Set("Accept", "application/json")
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	client := f.HTTP
	if client == nil {
		// Fallback timeout — http.DefaultClient has no deadline, so a
		// hung Supabase call would pin the request goroutine forever.
		// /audit/livehub M8. The production path always sets f.HTTP
		// to the worker's pooled client (main.go), so this branch is
		// only hit in tests + dev.
		client = &http.Client{Timeout: 30 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	// io.ReadAll surfaces a mid-stream read error (a truncated 2xx body)
	// as a fetch error rather than silently treating the partial bytes as
	// a complete success — so the authorizer fails closed (deny) instead
	// of reading a half-parsed run row. Mirrors zones.go's get().
	buf, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("supabase %d %s: %s", resp.StatusCode, path, string(buf))
	}
	return buf, nil
}
