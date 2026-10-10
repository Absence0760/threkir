package gpsdistance

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"
)

// The golden vectors are shared by every port. The path is relative to
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
	Name              string        `json:"name"`
	MaxSpeedMps       float64       `json:"maxSpeedMps"`
	ExpectedIntervalS float64       `json:"expectedIntervalS"`
	InitialStrideM    *float64      `json:"initialStrideM"`
	Events            []vectorEvent `json:"events"`
	Expected          struct {
		DistanceAfterEachEventM []float64 `json:"distanceAfterEachEventM"`
		GpsDistanceM            float64   `json:"gpsDistanceM"`
		StepDistanceM           float64   `json:"stepDistanceM"`
		StrideM                 *float64  `json:"strideM"`
		RejectedFixes           int       `json:"rejectedFixes"`
		ZuptFixes               int       `json:"zuptFixes"`
		RScale                  float64   `json:"rScale"`
		DopplerTrusted          bool      `json:"dopplerTrusted"`
		DopplerScale            float64   `json:"dopplerScale"`
	} `json:"expected"`
	Smoothed struct {
		DistanceAfterEachEventM []float64     `json:"distanceAfterEachEventM"`
		DistanceM               float64       `json:"distanceM"`
		GpsDistanceM            float64       `json:"gpsDistanceM"`
		StepDistanceM           float64       `json:"stepDistanceM"`
		StoppedFixes            int           `json:"stoppedFixes"`
		Positions               []*[2]float64 `json:"positions"`
	} `json:"smoothed"`
}

type vectorFile struct {
	Spec       string             `json:"spec"`
	ToleranceM float64            `json:"tolerance_m"`
	PosTolDeg  float64            `json:"position_tolerance_deg"`
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
	if vf.ToleranceM <= 0 || vf.PosTolDeg <= 0 {
		t.Fatalf("tolerance_m = %v, position_tolerance_deg = %v, want both > 0", vf.ToleranceM, vf.PosTolDeg)
	}
	return vf
}

func TestConstantsMatchTheVectorFile(t *testing.T) {
	vf := loadVectors(t)
	if vf.Spec != "gps-distance-estimator v"+SpecVersion || SpecVersion != "1.3" {
		t.Fatalf("vectors are for %q; this port implements v%s", vf.Spec, SpecVersion)
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
		"GATE_CHI2":                     GateChi2,
		"GATE_MAX_REJECTS":              GateMaxRejects,
		"R_SCALE_ALPHA":                 RScaleAlpha,
		"R_SCALE_MIN":                   RScaleMin,
		"R_SCALE_MAX":                   RScaleMax,
		"XCHECK_TAU_S":                  XcheckTauS,
		"XCHECK_MIN_S":                  XcheckMinS,
		"XCHECK_ENTER_ABS_MPS":          XcheckEnterAbsMps,
		"XCHECK_ENTER_REL":              XcheckEnterRel,
		"XCHECK_EXIT_ABS_MPS":           XcheckExitAbsMps,
		"XCHECK_EXIT_REL":               XcheckExitRel,
		"XCHECK_PERSIST_S":              XcheckPersistS,
		"XCHECK_MAX_SPAN_S":             XcheckMaxSpanS,
		"DEBIAS_FULL_MPS":               DebiasFullMps,
		"DEBIAS_ZERO_MPS":               DebiasZeroMps,
		"DSCALE_TAU_S":                  DscaleTauS,
		"DSCALE_MIN_S":                  DscaleMinS,
		"DSCALE_MIN":                    DscaleMin,
		"DSCALE_MAX":                    DscaleMax,
		"DSCALE_MIN_SPEED_MPS":          DscaleMinSpeedMps,
		"DSCALE_MAX_TURN_DEG":           DscaleMaxTurnDeg,
		"ZUPT_NO_STEP_S":                ZuptNoStepS,
		"ZUPT_VEL_SIGMA_MPS":            ZuptVelSigmaMps,
		"ZUPT_DOPPLER_OVERRIDE_MPS":     ZuptDopplerOverrideMps,
		"ZUPT_RELEASE_M":                ZuptReleaseM,
		"STOP_HALF_WINDOW_S":            StopHalfWindowS,
		"STOP_MIN_HALF_FIXES":           StopMinHalfFixes,
		"STOP_SPEED_MPS":                StopSpeedMps,
		"STOP_RADIUS_M":                 StopRadiusM,
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

func optionsOf(sc vectorScenario) Options {
	return Options{
		MaxSpeedMps:       sc.MaxSpeedMps,
		ExpectedIntervalS: sc.ExpectedIntervalS,
		InitialStrideM:    sc.InitialStrideM,
	}
}

func eventsOf(t *testing.T, sc vectorScenario) []Event {
	t.Helper()
	out := make([]Event, len(sc.Events))
	for i, ev := range sc.Events {
		switch ev.Type {
		case "fix":
			if ev.Lat == nil || ev.Lng == nil {
				t.Fatalf("event %d: fix without lat/lng", i)
			}
			out[i] = Event{Kind: EventFix, Fix: Fix{
				T: ev.T, Lat: *ev.Lat, Lng: *ev.Lng,
				AccuracyM: ev.Acc, SpeedMps: ev.Speed,
				SpeedAccuracyMps: ev.SpeedAcc, BearingDeg: ev.Bearing,
			}}
		case "steps":
			if ev.Count == nil {
				t.Fatalf("event %d: steps without count", i)
			}
			out[i] = Event{Kind: EventSteps, T: ev.T, Steps: *ev.Count}
		case "finish":
			out[i] = Event{Kind: EventFinish, T: ev.T}
		default:
			t.Fatalf("event %d: unknown type %q", i, ev.Type)
		}
	}
	return out
}

func TestGoldenVectors(t *testing.T) {
	vf := loadVectors(t)
	tol := vf.ToleranceM
	for _, sc := range vf.Scenarios {
		t.Run(sc.Name, func(t *testing.T) {
			if len(sc.Expected.DistanceAfterEachEventM) != len(sc.Events) {
				t.Fatalf("%d expectations for %d events", len(sc.Expected.DistanceAfterEachEventM), len(sc.Events))
			}
			e := NewWithOptions(optionsOf(sc))
			for i, ev := range eventsOf(t, sc) {
				switch ev.Kind {
				case EventFix:
					e.AddFix(ev.Fix)
				case EventSteps:
					e.AddSteps(ev.T, ev.Steps)
				case EventFinish:
					e.Finish(ev.T)
				}
				want := sc.Expected.DistanceAfterEachEventM[i]
				if got := e.DistanceM(); math.Abs(got-want) > tol {
					t.Fatalf("after event %d (t=%v): distance %.6f, want %.6f", i, ev.T, got, want)
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
			if e.RejectedFixes != sc.Expected.RejectedFixes {
				t.Errorf("rejectedFixes %d, want %d", e.RejectedFixes, sc.Expected.RejectedFixes)
			}
			if e.ZuptFixes != sc.Expected.ZuptFixes {
				t.Errorf("zuptFixes %d, want %d", e.ZuptFixes, sc.Expected.ZuptFixes)
			}
			if math.Abs(e.RScale-sc.Expected.RScale) > 1e-6 {
				t.Errorf("rScale %.9f, want %.9f", e.RScale, sc.Expected.RScale)
			}
			if math.Abs(e.DopplerScale-sc.Expected.DopplerScale) > 1e-6 {
				t.Errorf("dopplerScale %.9f, want %.9f", e.DopplerScale, sc.Expected.DopplerScale)
			}
			if e.DopplerTrusted != sc.Expected.DopplerTrusted {
				t.Errorf("dopplerTrusted %v, want %v", e.DopplerTrusted, sc.Expected.DopplerTrusted)
			}
		})
	}
}

func TestSmoothedGoldenVectors(t *testing.T) {
	vf := loadVectors(t)
	tol, ptol := vf.ToleranceM, vf.PosTolDeg
	for _, sc := range vf.Scenarios {
		t.Run(sc.Name, func(t *testing.T) {
			want := sc.Smoothed
			if len(want.DistanceAfterEachEventM) != len(sc.Events) || len(want.Positions) != len(sc.Events) {
				t.Fatalf("smoothed block does not have one entry per event (%d events)", len(sc.Events))
			}
			got := SmoothDistance(eventsOf(t, sc), optionsOf(sc))
			for i := range sc.Events {
				if math.Abs(got.CumulativeM[i]-want.DistanceAfterEachEventM[i]) > tol {
					t.Fatalf("after event %d: smoothed %.6f, want %.6f", i, got.CumulativeM[i], want.DistanceAfterEachEventM[i])
				}
				gp, wp := got.Positions[i], want.Positions[i]
				switch {
				case (gp == nil) != (wp == nil):
					t.Fatalf("event %d: position %v, want %v", i, gp, wp)
				case gp != nil && (math.Abs(gp.Lat-wp[0]) > ptol || math.Abs(gp.Lng-wp[1]) > ptol):
					t.Fatalf("event %d: position (%.10f, %.10f), want (%.10f, %.10f)", i, gp.Lat, gp.Lng, wp[0], wp[1])
				}
			}
			if math.Abs(got.DistanceM-want.DistanceM) > tol {
				t.Errorf("distanceM %.6f, want %.6f", got.DistanceM, want.DistanceM)
			}
			if math.Abs(got.GpsDistanceM-want.GpsDistanceM) > tol {
				t.Errorf("gpsDistanceM %.6f, want %.6f", got.GpsDistanceM, want.GpsDistanceM)
			}
			if math.Abs(got.StepDistanceM-want.StepDistanceM) > tol {
				t.Errorf("stepDistanceM %.6f, want %.6f", got.StepDistanceM, want.StepDistanceM)
			}
			if got.StoppedFixes != want.StoppedFixes {
				t.Errorf("stoppedFixes %d, want %d", got.StoppedFixes, want.StoppedFixes)
			}
		})
	}
}

// forwardWithStopHintsM is the reference forward estimator's distance over
// the scenarios whose post-hoc stop detection flags fixes that change it,
// replayed with those stop hints (python3 -I over reference.py: detect_stops,
// then GpsDistanceEstimator.add_fix(..., stopped_hint=...)). Every other
// scenario's forward pass is the fixture's own forward vector.
var forwardWithStopHintsM = map[string]float64{
	"stationary_position_only": 0.9846665773325164,
	"legacy_stop_clustering":   323.16068012777157,
}

func TestSmoothDistanceReportsItsForwardPass(t *testing.T) {
	vf := loadVectors(t)
	tol := vf.ToleranceM
	hinted := 0
	for _, sc := range vf.Scenarios {
		t.Run(sc.Name, func(t *testing.T) {
			got := SmoothDistance(eventsOf(t, sc), optionsOf(sc))
			if len(got.ForwardCumulativeM) != len(sc.Events) {
				t.Fatalf("forward cumulative has %d entries, want one per event (%d)", len(got.ForwardCumulativeM), len(sc.Events))
			}
			if want, ok := forwardWithStopHintsM[sc.Name]; ok {
				hinted++
				if got.StoppedFixes == 0 {
					t.Fatal("scenario listed as stop-hinted but the smoother flagged no fix")
				}
				if math.Abs(got.ForwardDistanceM-want) > tol {
					t.Errorf("forward distance %.6f, want %.6f", got.ForwardDistanceM, want)
				}
				if got.ForwardDistanceM >= sc.Expected.DistanceAfterEachEventM[len(sc.Events)-1] {
					t.Errorf("stop hints must remove stationary drift: %.6f is not below the unhinted %.6f",
						got.ForwardDistanceM, sc.Expected.DistanceAfterEachEventM[len(sc.Events)-1])
				}
				return
			}
			for i, want := range sc.Expected.DistanceAfterEachEventM {
				if math.Abs(got.ForwardCumulativeM[i]-want) > tol {
					t.Fatalf("after event %d: forward %.6f, want the fixture's %.6f", i, got.ForwardCumulativeM[i], want)
				}
			}
			if last := sc.Expected.DistanceAfterEachEventM[len(sc.Events)-1]; math.Abs(got.ForwardDistanceM-last) > tol {
				t.Errorf("forward distance %.6f, want %.6f", got.ForwardDistanceM, last)
			}
		})
	}
	if hinted != len(forwardWithStopHintsM) {
		t.Errorf("%d stop-hinted scenarios found in the fixture, want %d", hinted, len(forwardWithStopHintsM))
	}
}

func TestNewFallsBackToTheRunCeiling(t *testing.T) {
	for _, v := range []float64{0, -1, math.NaN(), math.Inf(1)} {
		if got := New(v).MaxSpeedMps; got != DefaultMaxSpeedMps {
			t.Errorf("New(%v).MaxSpeedMps = %v, want %v", v, got, DefaultMaxSpeedMps)
		}
	}
}

func TestNewWithOptionsZeroValueIsOneHertz(t *testing.T) {
	for _, it := range []float64{0, -3, 0.5, math.NaN(), math.Inf(1)} {
		e := NewWithOptions(Options{ExpectedIntervalS: it})
		if e.MaxSpeedMps != DefaultMaxSpeedMps {
			t.Errorf("interval %v: MaxSpeedMps = %v", it, e.MaxSpeedMps)
		}
		e.AddFix(Fix{T: 0, Lat: 40, Lng: -75})
		e.AddFix(Fix{T: 11, Lat: 40.0003, Lng: -75})
		if e.GpsDistanceM != 0 {
			t.Errorf("interval %v: an 11 s gap credited %v m", it, e.GpsDistanceM)
		}
	}
}

func TestNewWithOptionsSeedsOnlyAnInRangeStride(t *testing.T) {
	for _, tc := range []struct {
		in   float64
		keep bool
	}{{1.1, true}, {0.3, false}, {2.6, false}, {math.NaN(), false}} {
		in := tc.in
		e := NewWithOptions(Options{InitialStrideM: &in})
		if (e.StrideM != nil) != tc.keep || (tc.keep && *e.StrideM != in) {
			t.Errorf("initial stride %v: StrideM = %v", in, e.StrideM)
		}
	}
	if NewWithOptions(Options{}).StrideM != nil {
		t.Error("no initial stride should leave StrideM nil")
	}
}
