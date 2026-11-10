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
	LearnStride       bool          `json:"learnStride"`
	Events            []vectorEvent `json:"events"`
	Expected          struct {
		DistanceAfterEachEventM []float64 `json:"distanceAfterEachEventM"`
		GpsDistanceM            float64   `json:"gpsDistanceM"`
		StepDistanceM           float64   `json:"stepDistanceM"`
		StepOverChordM          float64   `json:"stepOverChordM"`
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
		StepOverChordM          float64       `json:"stepOverChordM"`
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
	if vf.Spec != "gps-distance-estimator v"+SpecVersion || SpecVersion != "1.7" {
		t.Fatalf("vectors are for %q; this port implements v%s", vf.Spec, SpecVersion)
	}
	ours := map[string]float64{
		"DEFAULT_SPEED_SIGMA_MPS":       DefaultSpeedSigmaMps,
		"EARTH_RADIUS_M":                EarthRadiusM,
		"FRESH_FIX_S":                   FreshFixS,
		"MAX_OPEN_GAPS":                 MaxOpenGaps,
		"GAP_S":                         GapS,
		"INIT_VEL_VAR":                  InitVelVar,
		"MAX_SPEED_SIGMA_MPS":           MaxSpeedSigmaMps,
		"MAX_STRIDE_M":                  MaxStrideM,
		"MIN_POS_SIGMA_M":               MinPosSigmaM,
		"MAX_POS_SIGMA_M":               MaxPosSigmaM,
		"STRIDE_MAX_SPEED_SIGMA_MPS":    StrideMaxSpeedSigmaMps,
		"STRIDE_MAX_POS_SIGMA_M":        StrideMaxPosSigmaM,
		"CHECK_MAX_POS_SIGMA_M":         CheckMaxPosSigmaM,
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
		"ZUPT_BATCH_MIN_CADENCE_SPS":    ZuptBatchMinCadenceSps,
		"ZUPT_BATCH_MARGIN":             ZuptBatchMargin,
		"ZUPT_MAX_NO_STEP_S":            ZuptMaxNoStepS,
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
		NoStrideLearning:  !sc.LearnStride,
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
			if math.Abs(e.StepOverChordM-sc.Expected.StepOverChordM) > tol {
				t.Errorf("stepOverChordM %.6f, want %.6f", e.StepOverChordM, sc.Expected.StepOverChordM)
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
			if math.Abs(got.StepOverChordM-want.StepOverChordM) > tol {
				t.Errorf("stepOverChordM %.6f, want %.6f", got.StepOverChordM, want.StepOverChordM)
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
	"zupt_batched_steps_stop":  291.6757193103465,
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
		// An 11 s interval is a gap at 1 s, credited only by its chord less the
		// 1-sigma uncertainty of both ends: sqrt(9 + 9 + 2*9) = 6 m.
		want := radians(0.0003)*EarthRadiusM - 6
		if math.Abs(e.GpsDistanceM-want) > 1e-6 {
			t.Errorf("interval %v: an 11 s gap credited %v m, want %v", it, e.GpsDistanceM, want)
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

func TestAFixWorseThanMaxPosSigmaIsIgnored(t *testing.T) {
	acc := func(v float64) *float64 { return &v }
	e := New(10)
	if got := e.AddFix(Fix{T: 0, Lat: 40, Lng: -75, AccuracyM: acc(51)}); got != 0 {
		t.Errorf("first fix credited %v", got)
	}
	e.AddFix(Fix{T: 1, Lat: 40, Lng: -75, AccuracyM: acc(50)})
	e.AddFix(Fix{T: 2, Lat: 40.00003, Lng: -75, AccuracyM: acc(51),
		SpeedMps: acc(3), SpeedAccuracyMps: acc(0.3), BearingDeg: acc(0)})
	if e.DistanceM() != 0 {
		t.Errorf("distance %v, want 0", e.DistanceM())
	}
}

func TestNoStrideLearningKeepsTheSeed(t *testing.T) {
	seed := 0.95
	for _, in := range []*float64{nil, &seed} {
		e := NewWithOptions(Options{InitialStrideM: in, NoStrideLearning: true})
		for i := 0; i < 120; i++ {
			acc, sp, sa, b := 4.0, 2.78, 0.3, 0.0
			e.AddFix(Fix{T: float64(i), Lat: 40 + float64(i)*0.000025, Lng: -75,
				AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
			e.AddSteps(float64(i)+0.5, (i+1)*3)
		}
		if (in == nil) != (e.StrideM == nil) || (in != nil && *e.StrideM != *in) {
			t.Errorf("seed %v: StrideM = %v", in, e.StrideM)
		}
	}
}

var eastMPerDeg = 111195 * math.Cos(40*math.Pi/180)

func eastwardV16() *Estimator {
	stride := 0.5
	e := NewWithOptions(Options{InitialStrideM: &stride, NoStrideLearning: true})
	for i := 0; i <= 25; i++ {
		acc, sp, sa, b := 3.0, 4.0, 0.3, 90.0
		e.AddFix(Fix{T: float64(i), Lat: 40, Lng: -75 + 4*float64(i)/eastMPerDeg,
			AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
		e.AddSteps(float64(i)+0.5, 4*i+2)
	}
	return e
}

// Steps at 0.5 m credit 2 m/s, so the straight 30 s gap's 116 m chord lower
// bound wins. The batch after the resuming fix moves 10 m of that credit from
// the chord to the steps and adds nothing (v1.6).
func TestALateStepBatchTopsAGapUpWithoutCountingItsChordTwice(t *testing.T) {
	e := eastwardV16()
	e.AddSteps(50, 202)
	acc, sp, sa, b := 3.0, 4.0, 0.3, 90.0
	e.AddFix(Fix{T: 55, Lat: 40, Lng: -75 + 220/eastMPerDeg,
		AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
	before, steps := e.DistanceM(), e.StepDistanceM
	e.AddSteps(56.5, 228)
	if math.Abs(e.DistanceM()-before) > 1e-9 {
		t.Errorf("distance %v, want %v", e.DistanceM(), before)
	}
	if math.Abs(e.StepDistanceM-steps-10) > 1e-9 {
		t.Errorf("step distance grew %v, want 10", e.StepDistanceM-steps)
	}
}

// 2 steps over (50, 51] at a 0.5 m stride credit 1 m; sharing the rest of the
// gap, which the fix at 55 closed before the sample arrived, at the sample's
// rate would credit 5 m (v1.6).
func TestALateSampleStampedInsideAGapSharesOnlyItsOwnInterval(t *testing.T) {
	e := eastwardV16()
	e.AddSteps(50, 202)
	acc, sp, sa, b := 3.0, 4.0, 0.3, 90.0
	e.AddFix(Fix{T: 55, Lat: 40, Lng: -75 + 110/eastMPerDeg,
		AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
	before, steps := e.DistanceM(), e.StepDistanceM
	e.AddSteps(51, 204)
	if math.Abs(e.DistanceM()-before-1) > 1e-9 {
		t.Errorf("distance grew %v, want 1", e.DistanceM()-before)
	}
	if math.Abs(e.StepDistanceM-steps-1) > 1e-9 {
		t.Errorf("step distance grew %v, want 1", e.StepDistanceM-steps)
	}
}

// 4 m/s at 4 steps/s is a 1 m stride. The fix at 36 bridges a 7 s stall whose
// samples emptied the window; feeding its 28 m to the window learns 1.092 m,
// and letting the sample at 36.5 refill it 0.985 m (v1.6).
func TestAFixBridgingAShortStallTeachesNoStrideFromItsCredit(t *testing.T) {
	e := NewWithOptions(Options{})
	for i := 0; i <= 60; i++ {
		if i < 30 || i >= 36 {
			acc, sp, sa, b := 3.0, 4.0, 0.3, 90.0
			e.AddFix(Fix{T: float64(i), Lat: 40, Lng: -75 + 4*float64(i)/eastMPerDeg,
				AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
		}
		e.AddSteps(float64(i)+0.5, 4*i+2)
	}
	if e.StrideM == nil || math.Abs(*e.StrideM-1) > 1e-9 {
		t.Errorf("stride %v, want 1", e.StrideM)
	}
}

// 4 m/s at 4 steps/s is a 1 m stride. The first sample, at 15.5, only sets the
// baseline; counting the window's metres from the first fix put 30 s of metres
// against 15 s of steps and learned 2.0 m, then 1.64 m by 60.5 (v1.6).
func TestTheFirstStepSampleOfAStretchStartsTheStrideWindow(t *testing.T) {
	e := NewWithOptions(Options{})
	for i := 0; i <= 60; i++ {
		acc, sp, sa, b := 3.0, 4.0, 0.3, 90.0
		e.AddFix(Fix{T: float64(i), Lat: 40, Lng: -75 + 4*float64(i)/eastMPerDeg,
			AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
		if i > 0 && i%15 == 0 {
			e.AddSteps(float64(i)+0.5, 4*i+2)
		}
	}
	if e.StrideM == nil || math.Abs(*e.StrideM-1) > 1e-6 {
		t.Errorf("stride %v, want 1", e.StrideM)
	}
}

// 4 m/s at 4 steps/s is a 1 m stride. The first sample, at 14.5, lands inside
// a 7 s stall the fix at 18 bridges, so it is stale as well as the baseline;
// the bridging fix must empty the window rather than feed it 28 m, which
// learned 1.171 m. (v1.6)
func TestAStaleFirstStepSampleKeepsABridgedStallOutOfTheStrideWindow(t *testing.T) {
	e := NewWithOptions(Options{})
	for i := 0; i <= 60; i++ {
		if i < 11 || i > 17 {
			acc, sp, sa, b := 3.0, 4.0, 0.3, 90.0
			e.AddFix(Fix{T: float64(i), Lat: 40, Lng: -75 + 4*float64(i)/eastMPerDeg,
				AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
		}
		if i%15 == 14 {
			e.AddSteps(float64(i)+0.5, 4*i+2)
		}
	}
	if e.StrideM == nil || math.Abs(*e.StrideM-1) > 1e-6 {
		t.Errorf("stride %v, want 1", e.StrideM)
	}
}

// The first sample, at 0.5, and the second, at 15.5, come before the first fix
// at 20; the first fix starts the window, so the sample at 30.5, whose
// interval began before it, empties the window rather than pairing 15 s of
// steps with 10 s of metres, which learned 0.787 m. (v1.6)
func TestTheFirstFixOfAStretchStartsTheStrideWindow(t *testing.T) {
	e := NewWithOptions(Options{})
	for i := 0; i <= 60; i++ {
		if i >= 20 {
			acc, sp, sa, b := 3.0, 4.0, 0.3, 90.0
			e.AddFix(Fix{T: float64(i), Lat: 40, Lng: -75 + 4*float64(i)/eastMPerDeg,
				AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
		}
		if i%15 == 0 {
			e.AddSteps(float64(i)+0.5, 4*i+2)
		}
	}
	if e.StrideM == nil || math.Abs(*e.StrideM-1) > 1e-6 {
		t.Errorf("stride %v, want 1", e.StrideM)
	}
}

// The baseline, stamped 15.5, is delivered after the fix at 18, so the
// window's metres start at 18; the sample at 30.5, whose steps start at 15.5,
// must empty the window rather than pair 15 s of steps with 12 s of metres,
// which learned 0.8 m. (v1.7)
func TestABaselineDeliveredAfterALaterFixKeepsItsStepsOutOfTheStrideWindow(t *testing.T) {
	e := NewWithOptions(Options{})
	for i := 0; i <= 60; i++ {
		acc, sp, sa, b := 3.0, 4.0, 0.3, 90.0
		e.AddFix(Fix{T: float64(i), Lat: 40, Lng: -75 + 4*float64(i)/eastMPerDeg,
			AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
		if i == 18 {
			e.AddSteps(15.5, 62)
		}
		if i > 15 && i%15 == 0 {
			e.AddSteps(float64(i)+0.5, 4*i+2)
		}
	}
	if e.StrideM == nil || math.Abs(*e.StrideM-1) > 1e-6 {
		t.Errorf("stride %v, want 1", e.StrideM)
	}
}

// A seeded 1 m stride, 4 m/s and 4 steps/s, then a 26 s fix gap whose 104 m
// of steps the resuming fix puts beside a chord lower bound of none (the
// runner looped back), 55.39 m, or more than the steps: stepOverChordM is
// what the steps credited over the chord, and none when the chord covers
// them (v1.7).
func TestStepOverChordCountsOnlyTheStepsBeyondTheChord(t *testing.T) {
	stride := 1.0
	acc, sp, sa, b := 3.0, 4.0, 0.3, 90.0
	for _, c := range []struct{ eastM, want float64 }{{24, 104}, {80, 48.612667}, {160, 0}} {
		e := NewWithOptions(Options{InitialStrideM: &stride, NoStrideLearning: true})
		for i := 0; i <= 30; i++ {
			if i <= 5 {
				e.AddFix(Fix{T: float64(i), Lat: 40, Lng: -75 + 4*float64(i)/eastMPerDeg,
					AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
			}
			e.AddSteps(float64(i)+0.5, 4*i+2)
		}
		e.AddFix(Fix{T: 31, Lat: 40, Lng: -75 + c.eastM/eastMPerDeg,
			AccuracyM: &acc, SpeedMps: &sp, SpeedAccuracyMps: &sa, BearingDeg: &b})
		e.AddSteps(31.5, 126)
		if math.Abs(e.StepDistanceM-104) > 1e-9 || math.Abs(e.StepOverChordM-c.want) > 1e-6 {
			t.Errorf("resume %v m east: steps %v, over chord %v; want 104, %v", c.eastM, e.StepDistanceM, e.StepOverChordM, c.want)
		}
	}
}

func TestAStretchCreditsNoStepsTakenBeforeItsFirstFix(t *testing.T) {
	stride := 1.0
	e := NewWithOptions(Options{InitialStrideM: &stride, NoStrideLearning: true})
	for i := 0; i < 30; i++ {
		e.AddSteps(float64(i)+0.5, 4*i)
	}
	acc := 3.0
	e.AddFix(Fix{T: 30, Lat: 40, Lng: -75, AccuracyM: &acc})
	e.Finish(31)
	if e.DistanceM() != 0 {
		t.Errorf("distance %v, want 0", e.DistanceM())
	}
}
