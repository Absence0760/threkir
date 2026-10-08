package internal

import (
	"math"
	"testing"
	"time"
)

// The same cases as apps/web/src/lib/integrations/embedded_best_efforts.test.ts
// and apps/mobile_android/test/embedded_bests_test.dart.

const ebMPerDeg = 6371000 * math.Pi / 180

var ebStart = time.Date(2026, 1, 1, 9, 0, 0, 0, time.UTC)

func ebPoint(lat, lng float64, at *time.Time) RecordedTrackPoint {
	return RecordedTrackPoint{Lat: &lat, Lng: &lng, Timestamp: at}
}

func ebAt(ms int64) *time.Time {
	t := ebStart.Add(time.Duration(ms) * time.Millisecond)
	return &t
}

// evenTrack is `segments` legs of stepM metres due east along the equator,
// stepS seconds apart.
func evenTrack(segments int, stepM, stepS float64) []RecordedTrackPoint {
	out := make([]RecordedTrackPoint, 0, segments+1)
	for i := 0; i <= segments; i++ {
		out = append(out, ebPoint(0, float64(i)*stepM/ebMPerDeg, ebAt(int64(float64(i)*stepS*1000))))
	}
	return out
}

// zigZagTrack is `segments` 1 s legs covering totalM due east, each fix
// ampM either side of the line — GPS noise the hop-sum turns into length.
func zigZagTrack(segments int, totalM, ampM float64) []RecordedTrackPoint {
	out := make([]RecordedTrackPoint, 0, segments+1)
	for i := 0; i <= segments; i++ {
		off := -ampM
		if i%2 == 1 {
			off = ampM
		}
		out = append(out, ebPoint(off/ebMPerDeg, float64(i)*(totalM/float64(segments))/ebMPerDeg, ebAt(int64(i)*1000)))
	}
	return out
}

// haversineCumulative is the raw hop-sum the bests used to be measured on.
func haversineCumulative(pts []RecordedTrackPoint) []float64 {
	rad := func(d float64) float64 { return d * math.Pi / 180 }
	cum := make([]float64, len(pts))
	for i := 1; i < len(pts); i++ {
		lat1, lat2 := rad(*pts[i-1].Lat), rad(*pts[i].Lat)
		dLat, dLng := lat2-lat1, rad(*pts[i].Lng-*pts[i-1].Lng)
		a := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(lat1)*math.Cos(lat2)*math.Sin(dLng/2)*math.Sin(dLng/2)
		cum[i] = cum[i-1] + 2*6371000*math.Asin(math.Min(1, math.Sqrt(a)))
	}
	return cum
}

func bestsOf(pts []RecordedTrackPoint) map[string]*int {
	pts = coordinatePoints(pts)
	cum, _, _ := replayRecordedTrack(pts, 10)
	return embeddedBestsOver(pts, cum)
}

func TestEmbeddedBestDistancesMatchTheDartAndWebKeys(t *testing.T) {
	want := []embeddedBestDistance{
		{"fastest_5k_s", 5000},
		{"fastest_10k_s", 10000},
		{"fastest_half_marathon_s", 21097.5},
		{"fastest_marathon_s", 42195},
	}
	if len(embeddedBestDistances) != len(want) {
		t.Fatalf("distances = %v", embeddedBestDistances)
	}
	for i, d := range want {
		if embeddedBestDistances[i] != d {
			t.Errorf("distance %d = %v, want %v", i, embeddedBestDistances[i], d)
		}
	}
}

func TestEmbeddedBests_FewerThanThreePointsWritesNothing(t *testing.T) {
	for col, v := range bestsOf(evenTrack(1, 100, 30)) {
		if v != nil {
			t.Errorf("%s = %d, want null", col, *v)
		}
	}
}

func TestEmbeddedBests_SubFiveKmTrackHasNoBests(t *testing.T) {
	for col, v := range bestsOf(evenTrack(40, 100, 30)) {
		if v != nil {
			t.Errorf("%s = %d, want null for 4 km", col, *v)
		}
	}
}

func TestEmbeddedBests_EvenSixKmRun(t *testing.T) {
	b := bestsOf(evenTrack(60, 100, 30))
	if s := b["fastest_5k_s"]; s == nil || *s < 1495 || *s > 1505 {
		t.Errorf("fastest_5k_s = %v, want ~1500", s)
	}
	if b["fastest_10k_s"] != nil {
		t.Errorf("fastest_10k_s = %d, want null", *b["fastest_10k_s"])
	}
}

func TestEmbeddedBests_FastFiveKmInsideALongRun(t *testing.T) {
	// 104 steps rather than 100 so the slow tail holds a 10 km window. The
	// smoother spreads the 2:1 pace change across both sides of it, so the
	// fast half credits ~8 m short and its best reads ~1016 s, not 1000.
	pts := []RecordedTrackPoint{ebPoint(0, 0, ebAt(0))}
	var ms int64
	for i := 1; i <= 104; i++ {
		if i <= 50 {
			ms += 20000
		} else {
			ms += 40000
		}
		pts = append(pts, ebPoint(0, float64(i)*100.01/ebMPerDeg, ebAt(ms)))
	}
	b := bestsOf(pts)
	if s := b["fastest_5k_s"]; s == nil || *s < 995 || *s > 1020 {
		t.Errorf("fastest_5k_s = %v, want 1000-1020", s)
	}
	if s := b["fastest_10k_s"]; s == nil || *s < 2990 || *s > 3040 {
		t.Errorf("fastest_10k_s = %v, want ~3000-3025", s)
	}
	if b["fastest_half_marathon_s"] != nil {
		t.Errorf("fastest_half_marathon_s = %d, want null", *b["fastest_half_marathon_s"])
	}
}

func TestEmbeddedBests_NoTimestampsWritesNothing(t *testing.T) {
	pts := evenTrack(60, 100, 30)
	for i := range pts {
		pts[i].Timestamp = nil
	}
	for col, v := range bestsOf(pts) {
		if v != nil {
			t.Errorf("%s = %d, want null", col, *v)
		}
	}
}

func TestFastestWindowSeconds_ShorterThanTheWindow(t *testing.T) {
	pts := evenTrack(10, 100, 30)
	if _, ok := fastestWindowSeconds(pts, haversineCumulative(pts), 5000); ok {
		t.Error("want no window in a 1 km track")
	}
}

func TestFastestWindowSeconds_ExactlyTheWindowStillYieldsABest(t *testing.T) {
	pts := evenTrack(50, 100, 30)
	exact := make([]float64, len(pts))
	for i := range exact {
		exact[i] = float64(i) * 100
	}
	if s, ok := fastestWindowSeconds(pts, exact, 5000); !ok || s != 1500 {
		t.Errorf("got %d, %v; want 1500", s, ok)
	}
}

func TestFastestWindowSeconds_TheToleranceNeverAdmitsARealShortfall(t *testing.T) {
	if windowToleranceRatio*42195 >= 0.001 {
		t.Fatal("tolerance wider than a millimetre on the marathon window")
	}
	pts := evenTrack(50, 100-0.001/50, 30)
	if _, ok := fastestWindowSeconds(pts, haversineCumulative(pts), 5000); ok {
		t.Error("a millimetre short of 5 km must not yield a 5 km best")
	}
}

func TestEmbeddedBests_GPSZigZagNoLongerClosesTheWindowEarly(t *testing.T) {
	pts := zigZagTrack(1800, 6000, 2)
	if raw, ok := fastestWindowSeconds(pts, haversineCumulative(pts), 5000); !ok || raw >= 1100 {
		t.Fatalf("fixture must be noisy: hop-sum 5k = %d, %v", raw, ok)
	}
	if s := bestsOf(pts)["fastest_5k_s"]; s == nil || *s < 1480 || *s > 1520 {
		t.Errorf("fastest_5k_s = %v, want ~1500", s)
	}
}

func TestEstimatorCumulative_NonDecreasingAndCarriesUntimedPoints(t *testing.T) {
	pts := make([]RecordedTrackPoint, 0, 21)
	for i := 0; i <= 20; i++ {
		at := ebAt(int64(i) * 1000)
		if i == 10 {
			at = nil
		}
		pts = append(pts, ebPoint(0, float64(i)*3/ebMPerDeg, at))
	}
	cum, _, fixes := replayRecordedTrack(pts, 10)
	if len(cum) != len(pts) || cum[0] != 0 || fixes != 20 {
		t.Fatalf("len = %d, cum[0] = %v, fixes = %d", len(cum), cum[0], fixes)
	}
	for i := 1; i < len(cum); i++ {
		if cum[i] < cum[i-1] {
			t.Errorf("dropped at %d", i)
		}
	}
	if cum[10] != cum[9] {
		t.Errorf("untimed point moved the cumulative: %v -> %v", cum[9], cum[10])
	}
}

func TestMedianFixIntervalS(t *testing.T) {
	if got := medianFixIntervalS(nil); got != 1 {
		t.Errorf("empty = %v, want 1", got)
	}
	pts := []RecordedTrackPoint{
		ebPoint(0, 0, ebAt(0)),
		ebPoint(0, 0, ebAt(1000)),
		ebPoint(0, 0, ebAt(1000)),
		ebPoint(0, 0, nil),
		ebPoint(0, 0, ebAt(2000)),
		ebPoint(0, 0, ebAt(7000)),
		ebPoint(0, 0, ebAt(67000)),
	}
	if got := medianFixIntervalS(pts); got != 3 {
		t.Errorf("median = %v, want 3", got)
	}
}
