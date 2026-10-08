package internal

import (
	"math"
	"sort"

	"github.com/Absence0760/threkir/apps/job_worker/internal/gpsdistance"
)

// The rolling embedded bests (runs.fastest_{5k,10k,half_marathon,marathon}_s)
// the distance recompute rewrites alongside distance_m. Port of
// `enrichMetadataWithEmbeddedBests` + `fastestWindowOf` +
// `estimatorCumulativeMetres` (apps/mobile_android/lib/embedded_bests.dart,
// run_stats.dart) and `computeEmbeddedBests` in
// apps/web/src/lib/integrations/garmin-fit.ts — same brackets, same window
// search, same rounding, so a recomputed best matches what a save would write.

type embeddedBestDistance struct {
	Column string
	Metres float64
}

var embeddedBestDistances = []embeddedBestDistance{
	{"fastest_5k_s", 5000},
	{"fastest_10k_s", 10000},
	{"fastest_half_marathon_s", 21097.5},
	{"fastest_marathon_s", 42195},
}

// windowToleranceRatio is Dart's windowToleranceRatio / web's
// WINDOW_TOLERANCE_RATIO: slack for float drift in an accumulated sum.
const windowToleranceRatio = 1e-9

func pointMs(p RecordedTrackPoint) (int64, bool) {
	if p.Timestamp == nil {
		return 0, false
	}
	return p.Timestamp.UnixMilli(), true
}

// coordinatePoints drops waypoints with a null coordinate, which the
// estimator cannot place and the window search cannot measure.
func coordinatePoints(pts []RecordedTrackPoint) []RecordedTrackPoint {
	out := make([]RecordedTrackPoint, 0, len(pts))
	for _, p := range pts {
		if p.Lat != nil && p.Lng != nil {
			out = append(out, p)
		}
	}
	return out
}

// medianFixIntervalS is the median of the positive intervals (seconds)
// between consecutive timestamped points; 1 when there are none. An even
// count takes the mean of the two middle values.
func medianFixIntervalS(pts []RecordedTrackPoint) float64 {
	var intervals []float64
	var prev int64
	havePrev := false
	for _, p := range pts {
		ms, ok := pointMs(p)
		if !ok {
			continue
		}
		if havePrev && ms > prev {
			intervals = append(intervals, float64(ms-prev)/1000)
		}
		prev, havePrev = ms, true
	}
	if len(intervals) == 0 {
		return 1
	}
	sort.Float64s(intervals)
	mid := len(intervals) / 2
	if len(intervals)%2 == 1 {
		return intervals[mid]
	}
	return (intervals[mid-1] + intervals[mid]) / 2
}

// replayRecordedTrack feeds every timestamped point of pts (all
// coordinate-bearing) through the spec-v1.1 estimator. It returns the
// cumulative distance after each point — an untimestamped point carries
// the previous value — the final distance, and how many fixes were fed.
// t is seconds since the first timestamped point; the expected interval is
// the median one, so a sparse watch track is not re-anchored on every fix.
func replayRecordedTrack(pts []RecordedTrackPoint, maxSpeedMps float64) (cumulative []float64, distanceM float64, fixes int) {
	est := gpsdistance.NewWithOptions(gpsdistance.Options{
		MaxSpeedMps:       maxSpeedMps,
		ExpectedIntervalS: medianFixIntervalS(pts),
		InitialStrideM:    nil,
	})
	cumulative = make([]float64, len(pts))
	var t0 int64
	var lastT float64
	for i, p := range pts {
		if ms, ok := pointMs(p); ok {
			if fixes == 0 {
				t0 = ms
			}
			lastT = float64(ms-t0) / 1000
			est.AddFix(gpsdistance.Fix{
				T:                lastT,
				Lat:              *p.Lat,
				Lng:              *p.Lng,
				AccuracyM:        p.AccuracyM,
				SpeedMps:         p.SpeedMps,
				SpeedAccuracyMps: p.SpeedAccuracyMps,
				BearingDeg:       p.BearingDeg,
			})
			fixes++
		}
		cumulative[i] = est.DistanceM()
	}
	if fixes > 0 {
		est.Finish(lastT)
	}
	return cumulative, est.DistanceM(), fixes
}

// fastestWindowSeconds is the fastest continuous windowMetres (whole
// seconds) over cum, the distance up to each point of pts; ok is false
// when the track is shorter than the window or has no timestamped window.
func fastestWindowSeconds(pts []RecordedTrackPoint, cum []float64, windowMetres float64) (int, bool) {
	n := len(pts)
	if n < 2 || windowMetres <= 0 || len(cum) != n {
		return 0, false
	}
	covers := windowMetres * (1 - windowToleranceRatio)
	if cum[n-1] < covers {
		return 0, false
	}
	var best int64
	found := false
	i := 0
	for j := 1; j < n; j++ {
		for i+1 < j && cum[j]-cum[i+1] >= covers {
			i++
		}
		if cum[j]-cum[i] < covers {
			continue
		}
		ti, okI := pointMs(pts[i])
		tj, okJ := pointMs(pts[j])
		if !okI || !okJ {
			continue
		}
		segDist := cum[i+1] - cum[i]
		startMs := ti
		if segDist > 0 {
			if ti1, ok := pointMs(pts[i+1]); ok {
				fraction := math.Min(1, math.Max(0, (cum[j]-windowMetres-cum[i])/segDist))
				startMs = ti + int64(math.Round(float64(ti1-ti)*fraction))
			}
		}
		windowMs := tj - startMs
		if windowMs <= 0 {
			continue
		}
		if !found || windowMs < best {
			best, found = windowMs, true
		}
	}
	if !found {
		return 0, false
	}
	return int(math.Round(float64(best) / 1000)), true
}

// embeddedBestsOver returns every fastest_* column keyed by name, nil
// where the track (fewer than 3 points, or too short) has no best — the
// recompute writes all four so a best the inflated hop-sum invented is
// cleared rather than left behind.
func embeddedBestsOver(pts []RecordedTrackPoint, cum []float64) map[string]*int {
	out := make(map[string]*int, len(embeddedBestDistances))
	for _, d := range embeddedBestDistances {
		out[d.Column] = nil
		if len(pts) < 3 {
			continue
		}
		if secs, ok := fastestWindowSeconds(pts, cum, d.Metres); ok && secs > 0 {
			s := secs
			out[d.Column] = &s
		}
	}
	return out
}
