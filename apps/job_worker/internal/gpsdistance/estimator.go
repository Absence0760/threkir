// Package gpsdistance is the Go port of the GPS distance estimator,
// spec v1.2 (docs/features/gps_distance.md). The reference implementation
// is scripts/gps_distance/reference.py and this file follows it
// operation for operation; every port replays
// fixtures/gps_distance_vectors.json to 1e-3 m, so a change here without
// the same change to the reference and the other ports fails the vector
// test.
//
// The worker uses it to recompute runs.distance_m from a stored track
// (kind='distance_recompute') through SmoothDistance, which is why it has
// no clock of its own: the caller supplies seconds on a clock monotonic
// within the run.
package gpsdistance

import "math"

// SpecVersion is the spec this port implements.
const SpecVersion = "1.2"

const (
	EarthRadiusM              = 6371008.8
	QAccel                    = 0.6 // m^2/s^3, white-acceleration spectral density
	MinPosSigmaM              = 3.0
	InitVelVar                = 25.0
	MinSpeedSigmaMps          = 0.3
	DefaultSpeedSigmaMps      = 0.5
	MaxSpeedSigmaMps          = 1.5
	StationarySpeedMps        = 0.4
	PosOnlyStationarySpeedMps = 0.8
	GapS                      = 10.0
	FreshFixS                 = 2.0
	StrideWindowSteps         = 50
	MinStrideM                = 0.4
	MaxStrideM                = 2.5
	StrideEMAAlpha            = 0.2

	GateChi2       = 13.8155
	GateMaxRejects = 5

	RScaleAlpha = 0.05
	RScaleMin   = 1.0
	RScaleMax   = 9.0

	XcheckTauS        = 60.0
	XcheckMinS        = 120.0
	XcheckEnterAbsMps = 0.4
	XcheckEnterRel    = 0.15
	XcheckExitAbsMps  = 0.2
	XcheckExitRel     = 0.08
	XcheckPersistS    = 60.0
	XcheckMaxSpanS    = 5.0

	DebiasFullMps = 0.5
	DebiasZeroMps = 1.0

	ZuptNoStepS            = 6.0
	ZuptVelSigmaMps        = 0.1
	ZuptDopplerOverrideMps = 1.0
	ZuptReleaseM           = 40.0

	StopHalfWindowS  = 20.0
	StopMinHalfFixes = 3
	StopSpeedMps     = 0.5
	StopRadiusM      = 10.0

	// DefaultMaxSpeedMps is the run ceiling, used when the caller has no
	// activity type to derive one from.
	DefaultMaxSpeedMps = 10.0
)

// axisState is one axis's [p, v] and covariance [[a, b], [b, c]].
type axisState struct {
	p, v    float64
	a, b, c float64
}

// axis is a 1-D constant-velocity Kalman filter.
type axis struct{ axisState }

func newAxis(p, posVar float64) *axis {
	return &axis{axisState{p: p, v: 0, a: posVar, b: 0, c: InitVelVar}}
}

func (s *axis) predict(dt float64) {
	s.p += s.v * dt
	a := s.a + 2.0*dt*s.b + dt*dt*s.c + QAccel*math.Pow(dt, 3)/3.0
	b := s.b + dt*s.c + QAccel*dt*dt/2.0
	c := s.c + QAccel*dt
	s.a, s.b, s.c = a, b, c
}

func (s *axis) updatePos(z, r float64) {
	sv := s.a + r
	k0, k1 := s.a/sv, s.b/sv
	y := z - s.p
	s.p += k0 * y
	s.v += k1 * y
	a, b, c := s.a, s.b, s.c
	s.a, s.b, s.c = (1-k0)*a, (1-k0)*b, c-k1*b
}

func (s *axis) updateVel(z, r float64) {
	sv := s.c + r
	k0, k1 := s.b/sv, s.c/sv
	y := z - s.v
	s.p += k0 * y
	s.v += k1 * y
	a, b, c := s.a, s.b, s.c
	s.a, s.b, s.c = a-k0*b, (1-k1)*b, (1-k1)*c
}

// resetPos is the gate lock-out re-anchor: position jumps to z, velocity is kept.
func (s *axis) resetPos(z, r float64) {
	s.p, s.a, s.b = z, r, 0
}

func finite(x float64) bool { return !math.IsNaN(x) && !math.IsInf(x, 0) }

func validPtr(x *float64) bool { return x != nil && finite(*x) }

func radians(deg float64) float64 { return deg * math.Pi / 180.0 }

func degrees(rad float64) float64 { return rad * 180.0 / math.Pi }

// wrapLng wraps a longitude difference (inputs within [-180, 180]) into [-180, 180).
func wrapLng(d float64) float64 {
	if d >= 180.0 {
		return d - 360.0
	}
	if d < -180.0 {
		return d + 360.0
	}
	return d
}

// dopplerSpeed is the usable, debiased Doppler speed and its sigma; ok is
// false when the reading is unusable.
func dopplerSpeed(speedMps, speedAccuracyMps *float64, maxSpeedMps float64) (s, sa float64, ok bool) {
	if !validPtr(speedMps) || *speedMps < 0 || *speedMps > maxSpeedMps {
		return 0, 0, false
	}
	reported := validPtr(speedAccuracyMps) && *speedAccuracyMps > 0
	sa = DefaultSpeedSigmaMps
	if reported {
		sa = *speedAccuracyMps
	}
	if sa > MaxSpeedSigmaMps {
		return 0, 0, false
	}
	s = *speedMps
	if reported && s < DebiasZeroMps {
		w := 1.0
		if s > DebiasFullMps {
			w = (DebiasZeroMps - s) / (DebiasZeroMps - DebiasFullMps)
		}
		s = math.Sqrt(math.Max(0, s*s-w*sa*sa))
	}
	return s, sa, true
}

// Fix is one GPS sample. The optional fields are nil when the platform
// did not report them (and on every track recorded before spec v1, which
// therefore takes the position-only path). StoppedHint says the caller
// knows the runner is stationary (post-hoc stop detection); live callers
// leave it false.
type Fix struct {
	T                float64
	Lat              float64
	Lng              float64
	AccuracyM        *float64
	SpeedMps         *float64
	SpeedAccuracyMps *float64
	BearingDeg       *float64
	StoppedHint      bool
}

// record is what the smoother needs from one forward-pass fix.
type record struct {
	anchor, chainBreak bool
	dt                 float64
	predX, predY       axisState
	x, y               axisState
	zupt               bool
	hasDop             bool
	dop                float64
	hasChord           bool
	chord              float64
	stepDistanceM      float64
}

// Estimator accumulates distance from a stream of fixes and pedometer
// counts. Not safe for concurrent use.
type Estimator struct {
	MaxSpeedMps   float64
	GpsDistanceM  float64
	StepDistanceM float64
	// StrideM is nil until a stride has been learned.
	StrideM *float64
	// Diagnostics (spec v1.2).
	RScale         float64
	RejectedFixes  int
	ZuptFixes      int
	DopplerTrusted bool

	gapS, freshFixS float64

	anchored   bool
	lat0, lng0 float64
	x, y       *axis
	hasT       bool
	t          float64

	winSteps     int
	winM         float64
	hasLastSteps bool
	lastSteps    int
	lastStepT    float64
	pendingStepM float64

	rejectStreak       int
	xcDoppler, xcPos   float64
	xcTime, xcPersistS float64
	xcLastX, xcLastY   float64
	xcLastT            float64
	stepsSeen          bool
	lastStepIncT       float64
	zuptReleased       bool
	hasZuptAnchor      bool
	zuptAnchorX        float64
	zuptAnchorY        float64

	recording bool
	records   []record
}

// Options configures NewWithOptions. The zero value is the 1 Hz default.
type Options struct {
	// MaxSpeedMps is the speed ceiling; non-positive or non-finite means
	// DefaultMaxSpeedMps.
	MaxSpeedMps float64
	// ExpectedIntervalS is the nominal fix interval. It scales the gap and
	// fresh-fix windows; non-finite or <= 1 means 1.
	ExpectedIntervalS float64
	// InitialStrideM seeds StrideM when finite and within
	// [MinStrideM, MaxStrideM]; otherwise it is ignored.
	InitialStrideM *float64
}

// New returns a 1 Hz estimator with the given speed ceiling (m/s). A
// non-positive or non-finite ceiling falls back to DefaultMaxSpeedMps.
func New(maxSpeedMps float64) *Estimator {
	return NewWithOptions(Options{MaxSpeedMps: maxSpeedMps})
}

func intervalScale(expectedIntervalS float64) float64 {
	if finite(expectedIntervalS) && expectedIntervalS > 1.0 {
		return expectedIntervalS
	}
	return 1.0
}

// NewWithOptions returns an estimator configured by o.
func NewWithOptions(o Options) *Estimator {
	maxSpeedMps := o.MaxSpeedMps
	if !finite(maxSpeedMps) || maxSpeedMps <= 0 {
		maxSpeedMps = DefaultMaxSpeedMps
	}
	scale := intervalScale(o.ExpectedIntervalS)
	e := &Estimator{
		MaxSpeedMps: maxSpeedMps, gapS: GapS * scale, freshFixS: FreshFixS * scale,
		RScale: 1.0, DopplerTrusted: true,
	}
	if validPtr(o.InitialStrideM) && *o.InitialStrideM >= MinStrideM && *o.InitialStrideM <= MaxStrideM {
		stride := *o.InitialStrideM
		e.StrideM = &stride
	}
	return e
}

// DistanceM is gpsDistance + stepDistance.
func (e *Estimator) DistanceM() float64 { return e.GpsDistanceM + e.StepDistanceM }

func (e *Estimator) project(lat, lng float64) (float64, float64) {
	x := radians(wrapLng(lng-e.lng0)) * EarthRadiusM * math.Cos(radians(e.lat0))
	y := radians(lat-e.lat0) * EarthRadiusM
	return x, y
}

// Unproject maps a local-plane point back to (lat, lng) degrees. Only
// meaningful once a fix has set the origin.
func (e *Estimator) Unproject(x, y float64) (float64, float64) {
	lat := e.lat0 + degrees(y/EarthRadiusM)
	lng := e.lng0 + degrees(x/(EarthRadiusM*math.Cos(radians(e.lat0))))
	return lat, wrapLng(lng)
}

// zuptDue: the pedometer says stationary — steps seen this run, none for
// ZuptNoStepS, and trusted Doppler not contradicting it.
func (e *Estimator) zuptDue(t float64, dopOK bool, dop float64) bool {
	if !e.stepsSeen || e.zuptReleased || t-e.lastStepIncT <= ZuptNoStepS {
		return false
	}
	return !(dopOK && e.DopplerTrusted && dop >= ZuptDopplerOverrideMps)
}

func (e *Estimator) record(r record) {
	if !e.recording {
		return
	}
	r.x, r.y = e.x.axisState, e.y.axisState
	r.stepDistanceM = e.StepDistanceM
	e.records = append(e.records, r)
}

// AddFix feeds one fix and returns the metres it credited.
func (e *Estimator) AddFix(f Fix) float64 {
	if !(finite(f.T) && finite(f.Lat) && finite(f.Lng)) {
		return 0
	}
	if !e.anchored {
		e.lat0, e.lng0 = f.Lat, f.Lng
		e.anchored = true
	}
	zx, zy := e.project(f.Lat, f.Lng)
	sigma := MinPosSigmaM
	if validPtr(f.AccuracyM) && *f.AccuracyM > 0 {
		sigma = *f.AccuracyM
	}
	rStated := math.Pow(math.Max(sigma, MinPosSigmaM), 2)
	r := math.Max(rStated*e.RScale, MinPosSigmaM*MinPosSigmaM)
	if e.hasT && f.T <= e.t {
		return 0
	}
	dop, sa, dopOK := dopplerSpeed(f.SpeedMps, f.SpeedAccuracyMps, e.MaxSpeedMps)
	if !e.hasT || f.T-e.t > e.gapS {
		// (Re-)anchor. Steps buffered across a real gap are committed now.
		if e.hasT {
			e.StepDistanceM += e.pendingStepM
		}
		e.pendingStepM = 0
		e.x, e.y = newAxis(zx, r), newAxis(zy, r)
		e.t, e.hasT = f.T, true
		e.xcLastX, e.xcLastY, e.xcLastT = zx, zy, f.T
		e.rejectStreak = 0
		e.hasZuptAnchor = false
		zupt := f.StoppedHint || e.zuptDue(f.T, dopOK, dop)
		e.record(record{anchor: true, chainBreak: true, zupt: zupt,
			hasDop: dopOK && e.DopplerTrusted, dop: dop})
		return 0
	}
	// The gap closed inside the gap window, so the filter integrates it: drop the buffer.
	e.pendingStepM = 0
	dt := f.T - e.t
	e.t = f.T
	e.x.predict(dt)
	e.y.predict(dt)
	predX, predY := e.x.axisState, e.y.axisState

	// 1. Innovation gate on the predicted position.
	yx, yy := zx-e.x.p, zy-e.y.p
	ax, ay := e.x.a, e.y.a
	nis := yx*yx/(ax+r) + yy*yy/(ay+r)
	chainBreak := false
	accepted := nis <= GateChi2
	if accepted {
		e.rejectStreak = 0
		e.x.updatePos(zx, r)
		e.y.updatePos(zy, r)
		// 2. Adaptive R: covariance matching, sample clamped, EMA, bounded.
		sample := ((yx*yx - ax) + (yy*yy - ay)) / (2.0 * rStated)
		sample = math.Min(math.Max(sample, 0), RScaleMax)
		ema := (1.0-RScaleAlpha)*e.RScale + RScaleAlpha*sample
		e.RScale = math.Min(math.Max(ema, RScaleMin), RScaleMax)
	} else {
		e.RejectedFixes++
		e.rejectStreak++
		if e.rejectStreak > GateMaxRejects {
			e.x.resetPos(zx, r)
			e.y.resetPos(zy, r)
			e.rejectStreak = 0
			e.xcLastX, e.xcLastY, e.xcLastT = zx, zy, f.T
			chainBreak = true
		}
	}

	// 3. Zero-velocity update (pedometer, or the caller's stop hint).
	pedZupt := e.zuptDue(f.T, dopOK, dop)
	hasChord, chord := false, 0.0
	if pedZupt {
		if !e.hasZuptAnchor {
			e.hasZuptAnchor, e.zuptAnchorX, e.zuptAnchorY = true, e.x.p, e.y.p
		} else {
			moved := math.Hypot(e.x.p-e.zuptAnchorX, e.y.p-e.zuptAnchorY)
			if moved > ZuptReleaseM {
				// The pedometer stalled while the runner moved: stop trusting it until it counts again.
				e.zuptReleased = true
				e.hasZuptAnchor = false
				pedZupt = false
				hasChord, chord = true, moved
			}
		}
	} else {
		e.hasZuptAnchor = false
	}
	zupt := f.StoppedHint || pedZupt
	if zupt {
		hasChord = false
		e.ZuptFixes++
		rz := ZuptVelSigmaMps * ZuptVelSigmaMps
		e.x.updateVel(0, rz)
		e.y.updateVel(0, rz)
	}

	// 4. Doppler-vs-position cross-check: Doppler speed against the raw
	//    fixes' displacement projected on the Doppler bearing.
	if accepted {
		span := f.T - e.xcLastT
		if dopOK && !zupt && validPtr(f.BearingDeg) &&
			dop >= PosOnlyStationarySpeedMps && span <= XcheckMaxSpanS {
			b := radians(*f.BearingDeg)
			u := ((zx-e.xcLastX)*math.Sin(b) + (zy-e.xcLastY)*math.Cos(b)) / span
			if e.xcTime == 0 {
				e.xcDoppler, e.xcPos = dop, dop
			} else {
				alpha := math.Min(1.0, span/XcheckTauS)
				e.xcDoppler += alpha * (dop - e.xcDoppler)
				e.xcPos += alpha * (u - e.xcPos)
			}
			e.xcTime += span
			if e.xcTime >= XcheckMinS {
				diff := math.Abs(e.xcDoppler - e.xcPos)
				ref := math.Abs(e.xcPos)
				var flip bool
				if e.DopplerTrusted {
					flip = diff > math.Max(XcheckEnterAbsMps, XcheckEnterRel*ref)
				} else {
					flip = diff < math.Max(XcheckExitAbsMps, XcheckExitRel*ref)
				}
				if flip {
					e.xcPersistS += span
				} else {
					e.xcPersistS = 0
				}
				if e.xcPersistS >= XcheckPersistS {
					e.DopplerTrusted = !e.DopplerTrusted
					e.xcPersistS = 0
				}
			}
		}
		e.xcLastX, e.xcLastY, e.xcLastT = zx, zy, f.T
	}

	// 5. Doppler velocity update.
	useDop := dopOK && e.DopplerTrusted
	if useDop && !zupt && validPtr(f.BearingDeg) && dop >= StationarySpeedMps {
		rv := math.Pow(math.Max(sa, MinSpeedSigmaMps), 2)
		b := radians(*f.BearingDeg)
		e.x.updateVel(dop*math.Sin(b), rv)
		e.y.updateVel(dop*math.Cos(b), rv)
	}

	// 6. Credit.
	var inc float64
	switch {
	case hasChord:
		inc = chord
	case zupt:
		inc = 0
	default:
		speed, floor := math.Hypot(e.x.v, e.y.v), PosOnlyStationarySpeedMps
		if useDop {
			speed, floor = dop, StationarySpeedMps
		}
		if speed >= floor {
			inc = math.Min(speed, e.MaxSpeedMps) * dt
		}
	}
	e.GpsDistanceM += inc
	e.winM += inc
	e.record(record{dt: dt, chainBreak: chainBreak, predX: predX, predY: predY, zupt: zupt,
		hasDop: useDop, dop: dop, hasChord: hasChord, chord: chord})
	return inc
}

// AddSteps feeds a cumulative pedometer count. Learns a stride while GPS
// is good; buffers steps x stride while it is not (committed only if the
// gap exceeds the gap window).
func (e *Estimator) AddSteps(t float64, cumulativeSteps int) {
	if !finite(t) {
		return
	}
	hadPrev, prev, prevT := e.hasLastSteps, e.lastSteps, e.lastStepT
	e.hasLastSteps, e.lastSteps, e.lastStepT = true, cumulativeSteps, t
	if !hadPrev || cumulativeSteps < prev || t <= prevT {
		return
	}
	d := cumulativeSteps - prev
	if d > 0 {
		e.stepsSeen = true
		e.lastStepIncT = t
		e.zuptReleased = false
	}
	if e.hasT && t-e.t <= e.freshFixS {
		e.winSteps += d
		if e.winSteps >= StrideWindowSteps {
			stride := e.winM / float64(e.winSteps)
			if stride >= MinStrideM && stride <= MaxStrideM {
				next := stride
				if e.StrideM != nil {
					next = (1-StrideEMAAlpha)*(*e.StrideM) + StrideEMAAlpha*stride
				}
				e.StrideM = &next
			}
			e.winSteps, e.winM = 0, 0
		}
		return
	}
	e.winSteps, e.winM = 0, 0
	if e.StrideM == nil {
		return
	}
	e.pendingStepM += math.Min(float64(d)*(*e.StrideM), e.MaxSpeedMps*(t-prevT))
}

// Finish ends the run: commits buffered steps if the trailing gap
// exceeds the gap window.
func (e *Estimator) Finish(t float64) {
	if e.hasT && finite(t) && t-e.t > e.gapS {
		e.StepDistanceM += e.pendingStepM
	}
	e.pendingStepM = 0
}
