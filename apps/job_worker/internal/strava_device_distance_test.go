package internal

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
)

// Strava's own `distance` stream is stamped on a webhook-ingested track as
// DistM when it validates, so the split table measures on it (#1387).
// Lockstep with apps/backend/supabase/functions/_shared/
// strava_device_distance.test.ts.

func rawNums(vals ...string) []json.RawMessage {
	out := make([]json.RawMessage, len(vals))
	for i, v := range vals {
		out[i] = json.RawMessage(v)
	}
	return out
}

func evenStravaStreams(n int, distanceOf func(i int) string) map[string]StravaStream {
	latlng := make([]string, n)
	tm := make([]string, n)
	dist := make([]string, n)
	for i := 0; i < n; i++ {
		latlng[i] = fmt.Sprintf("[0,%g]", float64(i)*100/111320)
		tm[i] = fmt.Sprintf("%d", i*30)
		dist[i] = distanceOf(i)
	}
	return map[string]StravaStream{
		"latlng":   {Data: rawNums(latlng...)},
		"time":     {Data: rawNums(tm...)},
		"distance": {Data: rawNums(dist...)},
	}
}

func distMs(track []TrackPoint) []float64 {
	out := make([]float64, len(track))
	for i, p := range track {
		if p.DistM == nil {
			return nil
		}
		out[i] = *p.DistM
	}
	return out
}

func TestDeviceCumulativeMetres_RebasesAMonotonicStream(t *testing.T) {
	got := deviceCumulativeMetres([]float64{12, 12, 40.5, 100}, 4)
	if !reflect.DeepEqual(got, []float64{0, 0, 28.5, 88}) {
		t.Fatalf("got %v", got)
	}
}

func TestDeviceCumulativeMetres_RefusesEveryStreamThatCannotStandIn(t *testing.T) {
	for name, c := range map[string]struct {
		s []float64
		n int
	}{
		"nil":         {nil, 3},
		"short":       {[]float64{0, 10}, 3},
		"one point":   {[]float64{0}, 1},
		"NaN":         {[]float64{0, math.NaN(), 20}, 3},
		"Inf":         {[]float64{0, math.Inf(1), 20}, 3},
		"negative":    {[]float64{-1, 0, 20}, 3},
		"backwards":   {[]float64{0, 30, 20}, 3},
		"all zero":    {[]float64{0, 0, 0}, 3},
		"no progress": {[]float64{55, 55, 55}, 3},
	} {
		if got := deviceCumulativeMetres(c.s, c.n); got != nil {
			t.Errorf("%s: got %v, want nil", name, got)
		}
	}
}

func TestBuildTrackFromStreams_StampsAValidDistanceStreamAsDistM(t *testing.T) {
	track := BuildTrackFromStreams(evenStravaStreams(61, func(i int) string { return fmt.Sprintf("%d", 40+i*100) }), "2026-01-01T09:00:00Z")
	got := distMs(track)
	if len(got) != 61 || got[0] != 0 || got[60] != 6000 {
		t.Fatalf("distM = %v", got)
	}
}

func TestBuildTrackFromStreams_InvalidOrAbsentDistanceLeavesNoDistM(t *testing.T) {
	for name, f := range map[string]func(i int) string{
		"null sample": func(i int) string {
			if i == 30 {
				return "null"
			}
			return fmt.Sprintf("%d", i*100)
		},
		"string sample": func(i int) string {
			if i == 30 {
				return `"x"`
			}
			return fmt.Sprintf("%d", i*100)
		},
		"step back": func(i int) string {
			if i == 30 {
				return "0"
			}
			return fmt.Sprintf("%d", i*100)
		},
		"no progress": func(int) string { return "0" },
	} {
		for _, p := range BuildTrackFromStreams(evenStravaStreams(61, f), "2026-01-01T09:00:00Z") {
			if p.DistM != nil {
				t.Errorf("%s: a point carries distM %v", name, *p.DistM)
				break
			}
		}
	}
	s := evenStravaStreams(3, func(i int) string { return "0" })
	delete(s, "distance")
	for _, p := range BuildTrackFromStreams(s, "2026-01-01T09:00:00Z") {
		if p.DistM != nil {
			t.Fatal("no distance stream must leave no distM")
		}
	}
	short := evenStravaStreams(3, func(i int) string { return fmt.Sprintf("%d", i*100) })
	short["distance"] = StravaStream{Data: rawNums("0")}
	for _, p := range BuildTrackFromStreams(short, "2026-01-01T09:00:00Z") {
		if p.DistM != nil {
			t.Fatal("a misaligned distance stream must leave no distM")
		}
	}
}

func TestBuildTrackFromStreams_DistMStaysAlignedWhenTheSanitiserDropsASample(t *testing.T) {
	streams := map[string]StravaStream{
		"latlng":   {Data: rawNums(`[45,-120]`, `[91,0]`, `[45.001,-120]`, `[45.002,-120]`)},
		"distance": {Data: rawNums(`10`, `60`, `121`, `232`)},
	}
	got := distMs(BuildTrackFromStreams(streams, "2026-01-01T09:00:00Z"))
	if !reflect.DeepEqual(got, []float64{0, 111, 222}) {
		t.Fatalf("distM = %v", got)
	}
}

func TestStravaFetchStreams_RequestsTheDistanceStream(t *testing.T) {
	var keys string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		keys = r.URL.Query().Get("keys")
		_, _ = w.Write([]byte(`{}`))
	}))
	defer srv.Close()
	c := &StravaClient{BaseURL: srv.URL}
	if _, err := c.FetchStreams(context.Background(), "at", 123); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(","+keys+",", ",distance,") {
		t.Fatalf("keys=%q, want distance among them", keys)
	}
}
