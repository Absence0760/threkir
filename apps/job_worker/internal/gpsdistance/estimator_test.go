package gpsdistance

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"
)

// The golden vectors are shared by all six ports. The path is relative to
// this package directory: apps/job_worker/internal/gpsdistance -> repo root.
var vectorsPath = filepath.Join("..", "..", "..", "..", "fixtures", "gps_distance_vectors.json")

type vectorEvent struct {
	Type     string   `json:"type"`
	T        float64  `json:"t"`
	Lat      *float64 `json:"lat"`
	Lng      *float64 `json:"lng"`
	Acc      *float64 `json:"acc"`
	Speed    *float64 `json:"speed"`
	SpeedAcc *float64 `json:"speedAcc"`
	Bearing  *float64 `json:"bearing"`
	Count    *int     `json:"count"`
}

type vectorScenario struct {
	Name        string        `json:"name"`
	MaxSpeedMps float64       `json:"maxSpeedMps"`
	Events      []vectorEvent `json:"events"`
	Expected    struct {
		DistanceAfterEachEventM []float64 `json:"distanceAfterEachEventM"`
		GpsDistanceM            float64   `json:"gpsDistanceM"`
		StepDistanceM           float64   `json:"stepDistanceM"`
		StrideM                 *float64  `json:"strideM"`
	} `json:"expected"`
}

type vectorFile struct {
	Spec       string             `json:"spec"`
	ToleranceM float64            `json:"tolerance_m"`
	Constants  map[string]float64 `json:"constants"`
	Scenarios  []vectorScenario   `json:"scenarios"`
}

func loadVectors(t *testing.T) vectorFile {
	t.Helper()
	raw, err := os.ReadFile(vectorsPath)
	if err != nil {
		t.Fatalf("read %s: %v", vectorsPath, err)
	}
	var vf vectorFile
	if err := json.Unmarshal(raw, &vf); err != nil {
		t.Fatalf("decode vectors: %v", err)
	}
	if len(vf.Scenarios) == 0 {
		t.Fatal("vector file holds no scenarios — the test would pass vacuously")
	}
	if vf.ToleranceM <= 0 {
		t.Fatalf("tolerance_m = %v, want > 0", vf.ToleranceM)
	}
	return vf
}

func TestConstantsMatchTheVectorFile(t *testing.T) {
	vf := loadVectors(t)
	if vf.Spec != "gps-distance-estimator v1" {
		t.Fatalf("vectors are for %q; this port implements v1", vf.Spec)
	}
	ours := map[string]float64{
		"DEFAULT_SPEED_SIGMA_MPS":       DefaultSpeedSigmaMps,
		"EARTH_RADIUS_M":                EarthRadiusM,
		"FRESH_FIX_S":                   FreshFixS,
		"GAP_S":                         GapS,
		"INIT_VEL_VAR":                  InitVelVar,
		"MAX_SPEED_SIGMA_MPS":           MaxSpeedSigmaMps,
		"MAX_STRIDE_M":                  MaxStrideM,
		"MIN_POS_SIGMA_M":               MinPosSigmaM,
		"MIN_SPEED_SIGMA_MPS":           MinSpeedSigmaMps,
		"MIN_STRIDE_M":                  MinStrideM,
		"POS_ONLY_STATIONARY_SPEED_MPS": PosOnlyStationarySpeedMps,
		"Q_ACCEL":                       QAccel,
		"STATIONARY_SPEED_MPS":          StationarySpeedMps,
		"STRIDE_EMA_ALPHA":              StrideEMAAlpha,
		"STRIDE_WINDOW_STEPS":           StrideWindowSteps,
	}
	for k, want := range vf.Constants {
		got, ok := ours[k]
		if !ok {
			t.Errorf("vector constant %s has no Go counterpart", k)
			continue
		}
		if got != want {
			t.Errorf("%s = %v, vectors say %v", k, got, want)
		}
	}
	if len(ours) != len(vf.Constants) {
		t.Errorf("Go declares %d constants, vectors %d", len(ours), len(vf.Constants))
	}
}

func TestGoldenVectors(t *testing.T) {
	vf := loadVectors(t)
	tol := vf.ToleranceM
	for _, sc := range vf.Scenarios {
		t.Run(sc.Name, func(t *testing.T) {
			if len(sc.Expected.DistanceAfterEachEventM) != len(sc.Events) {
				t.Fatalf("%d expectations for %d events", len(sc.Expected.DistanceAfterEachEventM), len(sc.Events))
			}
			e := New(sc.MaxSpeedMps)
			for i, ev := range sc.Events {
				switch ev.Type {
				case "fix":
					if ev.Lat == nil || ev.Lng == nil {
						t.Fatalf("event %d: fix without lat/lng", i)
					}
					e.AddFix(Fix{
						T: ev.T, Lat: *ev.Lat, Lng: *ev.Lng,
						AccuracyM: ev.Acc, SpeedMps: ev.Speed,
						SpeedAccuracyMps: ev.SpeedAcc, BearingDeg: ev.Bearing,
					})
				case "steps":
					if ev.Count == nil {
						t.Fatalf("event %d: steps without count", i)
					}
					e.AddSteps(ev.T, *ev.Count)
				case "finish":
					e.Finish(ev.T)
				default:
					t.Fatalf("event %d: unknown type %q", i, ev.Type)
				}
				want := sc.Expected.DistanceAfterEachEventM[i]
				if got := e.DistanceM(); math.Abs(got-want) > tol {
					t.Fatalf("after event %d (%s t=%v): distance %.6f, want %.6f", i, ev.Type, ev.T, got, want)
				}
			}
			if math.Abs(e.GpsDistanceM-sc.Expected.GpsDistanceM) > tol {
				t.Errorf("gpsDistanceM %.6f, want %.6f", e.GpsDistanceM, sc.Expected.GpsDistanceM)
			}
			if math.Abs(e.StepDistanceM-sc.Expected.StepDistanceM) > tol {
				t.Errorf("stepDistanceM %.6f, want %.6f", e.StepDistanceM, sc.Expected.StepDistanceM)
			}
			switch {
			case sc.Expected.StrideM == nil && e.StrideM != nil:
				t.Errorf("strideM %.6f, want absent", *e.StrideM)
			case sc.Expected.StrideM != nil && e.StrideM == nil:
				t.Errorf("strideM absent, want %.6f", *sc.Expected.StrideM)
			case sc.Expected.StrideM != nil && math.Abs(*e.StrideM-*sc.Expected.StrideM) > tol:
				t.Errorf("strideM %.6f, want %.6f", *e.StrideM, *sc.Expected.StrideM)
			}
		})
	}
}

func TestNewFallsBackToTheRunCeiling(t *testing.T) {
	for _, v := range []float64{0, -1, math.NaN(), math.Inf(1)} {
		if got := New(v).MaxSpeedMps; got != DefaultMaxSpeedMps {
			t.Errorf("New(%v).MaxSpeedMps = %v, want %v", v, got, DefaultMaxSpeedMps)
		}
	}
}
