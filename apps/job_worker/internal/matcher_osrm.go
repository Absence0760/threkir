package internal

// OSRMMatcher: real map matching via the OSRM `/match/v1/foot`
// endpoint. Replaces PassthroughMatcher whenever the worker has an
// OSRM_URL configured. The interface stays the same — the worker
// loop, the run_matched_tracks write path, the auto-link step are
// all engine-agnostic; only the geometry transformation changes.
//
// Why /match and not /route: OSRM's match service runs an HMM over a
// noisy GPS track and snaps each input point to the nearest plausible
// road segment, weighted by movement consistency. /route picks one
// fastest path between A and B and ignores the points in between.
// For a 5 km run with 1500 GPS samples, /match is the only sensible
// choice.
//
// Profile is hard-coded to `foot` because the graph is built with
// foot.lua (see the OSRM Makefile). Bicycle / car profiles would need
// their own graphs and a different default in the URL — different
// engine, different deploy.
//
// Output is the input trace with every point's POSITION corrected, not
// the road geometry OSRM would draw between them. `ele`, `ts` and `bpm`
// are per-sample measurements, and the response's `tracepoints` array
// is what makes carrying them possible: it holds one entry per input
// coordinate, in input order, so each snapped location can be paired
// with the sample it came from. Reading `matchings[].geometry` instead
// — which is what this matcher used to do — yields road-network
// vertices that belong to no sample, so the three optional fields have
// nowhere to go and were dropped; `/runs/[id]` prefers the matched
// track, so the elevation profile disappeared and the pace heatmap fell
// back to a flat line for every run recorded with altitude or a strap
// (decisions § 1171).
//
// Match is therefore LENGTH-PRESERVING: one output point per input
// point, in order. A caller may index the two against each other.
//
// Error model:
//   * Network / 5xx → returned as an error so the worker's transient
//     classifier defers the job.
//   * 200 with `code != "Ok"`, no matchings, or a `tracepoints` array
//     that does not index this chunk's input → the engine gave us
//     nothing we can attribute to a sample. We carry that chunk's raw
//     input points through rather than drop them, so the matched track
//     always covers the WHOLE run with mixed snapped + raw positions.
//   * A `null` tracepoint (OSRM's outlier signal) or one whose
//     `location` is not a coordinate pair → that one sample carries
//     through raw, for the same reason: the measurement it holds is not
//     the engine's to discard.

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
	"time"
)

// OSRMMatcher calls a self-hosted OSRM `osrm-routed` server. baseURL
// is the root, e.g., "http://127.0.0.1:5000". Algorithm + version
// strings get persisted onto run_matched_tracks so future re-matches
// (engine upgrade, different graph build) can be triggered when one
// changes.
type OSRMMatcher struct {
	BaseURL    string
	HTTPClient *http.Client
	// ChunkSize is the max number of points per /match call. OSRM's
	// default URL length cap chokes on 200+ point tracks, and the
	// engine's HMM gets noisy beyond ~100 points anyway. Chunked
	// matches preserve resolution; the worker stitches them back
	// together. Defaults to 100 if zero.
	ChunkSize int
	// Version: bumped when the engine itself changes (image tag
	// upgrade, profile retune). Pairs with Algorithm to form the
	// re-match key on run_matched_tracks.
	AlgVersion string
}

// NewOSRMMatcher constructs the default-configured matcher. Caller
// supplies the URL; everything else takes a sane default. The HTTP
// client gets a timeout because long matches under load can otherwise
// pin a worker to a single job for minutes.
func NewOSRMMatcher(baseURL string) *OSRMMatcher {
	return &OSRMMatcher{
		BaseURL:    strings.TrimRight(baseURL, "/"),
		HTTPClient: &http.Client{Timeout: 60 * time.Second},
		ChunkSize:  100,
		AlgVersion: "v1",
	}
}

func (m *OSRMMatcher) Algorithm() string { return "osrm" }
func (m *OSRMMatcher) Version() string {
	if m.AlgVersion == "" {
		return "v1"
	}
	return m.AlgVersion
}

// Match runs each chunk through OSRM's /match endpoint and stitches the
// snapped tracepoints back together. Empty input → empty output;
// otherwise one output point per input point, carrying that point's
// `ele` / `ts` / `bpm` across unchanged.
func (m *OSRMMatcher) Match(ctx context.Context, points []TrackPoint) ([]TrackPoint, error) {
	out, _, err := m.MatchWithRoadDistance(ctx, points)
	return out, err
}

// MatchWithRoadDistance is Match plus the matched track's length along
// the road graph: each chunk's single matching `distance`, joined by the
// great-circle hop between one chunk's last snapped point and the next
// chunk's first. The length is reported only when every chunk matched as
// ONE matching with every tracepoint snapped — a chunk carried through raw,
// split into several matchings, or holding an outlier has a stretch the
// engine never measured, and a sum that skipped it would under-read.
func (m *OSRMMatcher) MatchWithRoadDistance(ctx context.Context, points []TrackPoint) ([]TrackPoint, RoadMatch, error) {
	if len(points) < 2 {
		return nil, RoadMatch{}, nil
	}
	chunkSize := m.ChunkSize
	if chunkSize <= 0 {
		chunkSize = 100
	}

	out := make([]TrackPoint, 0, len(points))
	whole := true
	roadM, minConfidence := 0.0, 1.0
	var prevEnd TrackPoint
	havePrev := false
	join := func(next TrackPoint, last TrackPoint) {
		if havePrev {
			roadM += haversineM(prevEnd, next)
		}
		prevEnd, havePrev = last, true
	}
	for start := 0; start < len(points); start += chunkSize {
		end := start + chunkSize
		if end > len(points) {
			end = len(points)
		}
		chunk := points[start:end]
		if len(chunk) < 2 {
			// Tail of 1 point left over from the chunking. /match
			// requires 2+. Carry the original through verbatim so
			// the matched track ends where the raw track ends.
			out = append(out, chunk...)
			join(chunk[0], chunk[0])
			continue
		}
		matched, ok, road, err := m.matchChunk(ctx, chunk)
		if err != nil {
			return nil, RoadMatch{}, err
		}
		if !ok {
			whole = false
			// The engine couldn't align this chunk (code != "Ok": a
			// tunnel gap, an unmapped trail, a too-noisy stretch).
			// Dropping it and continuing would silently discard this
			// chunk's span from a track we still label 'matched',
			// truncating coverage of the run. Carry the raw input
			// points through instead — same passthrough as the
			// 1-point tail above — so the matched track covers the
			// WHOLE run with mixed snapped + raw positions.
			out = append(out, chunk...)
			continue
		}
		if road == nil {
			whole = false
		} else {
			roadM += road.distanceM
			minConfidence = math.Min(minConfidence, road.confidence)
		}
		join(matched[0], matched[len(matched)-1])
		out = append(out, matched...)
	}
	if !whole {
		return out, RoadMatch{}, nil
	}
	return out, RoadMatch{DistanceM: &roadM, MinConfidence: minConfidence}, nil
}

// chunkRoad is one chunk's along-road length and the engine's confidence
// in it.
type chunkRoad struct {
	distanceM  float64
	confidence float64
}

// matchChunk returns the snapped points for one chunk, one per input
// point and in input order. The bool is false when OSRM replied 200 but
// gave nothing this chunk's samples can be attributed to (code != "Ok",
// no matchings, or a `tracepoints` array of the wrong length) — distinct
// from (nil, true) so the caller can fall back to the raw input rather
// than silently dropping the span. The chunkRoad is non-nil only when the
// chunk matched as one matching with every tracepoint snapped and a
// usable distance and confidence.
func (m *OSRMMatcher) matchChunk(ctx context.Context, chunk []TrackPoint) ([]TrackPoint, bool, *chunkRoad, error) {
	// OSRM's URL format: /match/v1/{profile}/{lng,lat;lng,lat;...}
	// Coordinates are lng-first, semicolon-separated. Building the
	// path manually avoids URL-encoding overhead on a hot path.
	var sb strings.Builder
	sb.WriteString(m.BaseURL)
	sb.WriteString("/match/v1/foot/")
	for i, p := range chunk {
		if i > 0 {
			sb.WriteByte(';')
		}
		fmt.Fprintf(&sb, "%.6f,%.6f", p.Lng, p.Lat)
	}
	// `overview=false` because the route geometry is not what we read
	// — `tracepoints` is, and it is returned regardless. `tidy` is
	// deliberately left off: it drops input points the engine considers
	// redundant, and every dropped point is now a lost heart-rate
	// sample and a lost timestamp rather than a tidier line.
	sb.WriteString("?overview=false")

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, sb.String(), nil)
	if err != nil {
		return nil, false, nil, err
	}
	resp, err := m.HTTPClient.Do(req)
	if err != nil {
		return nil, false, nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, false, nil, err
	}
	if resp.StatusCode != http.StatusOK {
		// Surface the OSRM error verbatim — it's small JSON like
		// `{"code":"InvalidUrl","message":"URL is invalid"}`. The
		// worker's transient classifier picks up 5xx as defer-worthy.
		return nil, false, nil, &HTTPError{StatusCode: resp.StatusCode, Body: string(body)}
	}

	var resp2 osrmMatchResponse
	if err := json.Unmarshal(body, &resp2); err != nil {
		return nil, false, nil, fmt.Errorf("decode osrm response: %w", err)
	}
	// `code != "Ok"` → engine didn't find a sufficiently confident
	// alignment for this chunk. Report not-matched so the caller carries
	// the chunk's raw input points through, keeping full run coverage.
	if resp2.Code != "Ok" || len(resp2.Matchings) == 0 {
		return nil, false, nil, nil
	}
	// One tracepoint per input coordinate is the contract that lets a
	// snapped location be paired with the sample it came from. A
	// response of any other length indexes something else, and pairing
	// against it would attach one sample's heart rate to another
	// sample's position — worse than not matching the chunk at all.
	if len(resp2.Tracepoints) != len(chunk) {
		return nil, false, nil, nil
	}

	out := make([]TrackPoint, 0, len(chunk))
	allSnapped := true
	for i, tp := range resp2.Tracepoints {
		p := chunk[i]
		if tp != nil && len(tp.Location) >= 2 {
			p.Lng, p.Lat = tp.Location[0], tp.Location[1]
		} else {
			allSnapped = false
		}
		out = append(out, p)
	}
	var road *chunkRoad
	if mt := resp2.Matchings; allSnapped && len(mt) == 1 && mt[0].Distance != nil &&
		isFiniteNonNeg(*mt[0].Distance) && isFiniteNonNeg(mt[0].Confidence) {
		road = &chunkRoad{distanceM: *mt[0].Distance, confidence: mt[0].Confidence}
	}
	return out, true, road, nil
}

func isFiniteNonNeg(v float64) bool {
	return !math.IsNaN(v) && !math.IsInf(v, 0) && v >= 0
}

// osrmMatchResponse is the subset of OSRM's /match response we read.
// Schema is documented at https://project-osrm.org/docs/v5.24.0/api/#match-service.
//
// `Tracepoints` carries one entry per input coordinate in input order,
// or `null` where the engine treated that coordinate as an outlier.
// `Matchings`: `code == "Ok"` with an empty array is the engine declining
// the chunk; a single matching's `distance` (metres along the matched
// route) and `confidence` (0..1) feed the road distance.
type osrmMatchResponse struct {
	Code        string `json:"code"`
	Tracepoints []*struct {
		Location []float64 `json:"location"` // [lng, lat]
	} `json:"tracepoints"`
	Matchings []struct {
		Confidence float64  `json:"confidence"`
		Distance   *float64 `json:"distance"`
	} `json:"matchings"`
}
