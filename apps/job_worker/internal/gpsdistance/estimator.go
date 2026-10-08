// Package gpsdistance is the Go port of the GPS distance estimator,
// spec v1.1 (docs/features/gps_distance.md). The reference implementation
// is scripts/gps_distance/reference.py and this file follows it
// operation for operation; every port replays
// fixtures/gps_distance_vectors.json to 1e-3 m, so a change here without
// the same change to the reference and the other five ports fails the
// vector test.
//
// The worker uses it to recompute runs.distance_m from a stored track
// (kind='distance_recompute'), which is why it has no clock of its own:
// the caller supplies seconds on a clock monotonic within the run.
package gpsdistance

import "math"

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

	// DefaultMaxSpeedMps is the run ceiling, used when the caller has no
	// activity type to derive one from.
	DefaultMaxSpeedMps = 10.0
)

// axis is a 1-D constant-velocity Kalman filter: state [p, v],
// covariance [[a, b], [b, c]].
type axis struct {
	p, v    float64
	a, b, c float64
}

func newAxis(p, posVar float64) *axis {
	return &axis{p: p, v: 0, a: posVar, b: 0, c: InitVelVar}
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

func finite(x float64) bool { return !math.IsNaN(x) && !math.IsInf(x, 0) }

func validPtr(x *float64) bool { return x != nil && finite(*x) }

func radians(deg float64) float64 { return deg * math.Pi / 180.0 }

// Fix is one GPS sample. The optional fields are nil when the platform
// did not report them (and on every track recorded before spec v1, which
// therefore takes the position-only path).
type Fix struct {
	T                float64
	Lat              float64
	Lng              float64
	AccuracyM        *float64
	SpeedMps         *float64
	SpeedAccuracyMps *float64
	BearingDeg       *float64
}

// Estimator accumulates distance from a stream of fixes and pedometer
// counts. Not safe for concurrent use.
type Estimator struct {
	MaxSpeedMps   float64
	GpsDistanceM  float64
	StepDistanceM float64
	// StrideM is nil until a stride has been learned.
	StrideM *float64

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

// NewWithOptions returns an estimator configured by o.
func NewWithOptions(o Options) *Estimator {
	maxSpeedMps := o.MaxSpeedMps
	if !finite(maxSpeedMps) || maxSpeedMps <= 0 {
		maxSpeedMps = DefaultMaxSpeedMps
	}
	scale := 1.0
	if finite(o.ExpectedIntervalS) && o.ExpectedIntervalS > 1.0 {
		scale = o.ExpectedIntervalS
	}
	e := &Estimator{MaxSpeedMps: maxSpeedMps, gapS: GapS * scale, freshFixS: FreshFixS * scale}
	if validPtr(o.InitialStrideM) && *o.InitialStrideM >= MinStrideM && *o.InitialStrideM <= MaxStrideM {
		stride := *o.InitialStrideM
		e.StrideM = &stride
	}
	return e
}

// DistanceM is gpsDistance + stepDistance.
func (e *Estimator) DistanceM() float64 { return e.GpsDistanceM + e.StepDistanceM }

func (e *Estimator) project(lat, lng float64) (float64, float64) {
	x := radians(lng-e.lng0) * EarthRadiusM * math.Cos(radians(e.lat0))
	y := radians(lat-e.lat0) * EarthRadiusM
	return x, y
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
	r := math.Pow(math.Max(sigma, MinPosSigmaM), 2)
	if e.hasT && f.T <= e.t {
		return 0
	}
	if !e.hasT || f.T-e.t > e.gapS {
		// (Re-)anchor. Steps buffered across a real gap are committed now.
		if e.hasT {
			e.StepDistanceM += e.pendingStepM
		}
		e.pendingStepM = 0
		e.x, e.y = newAxis(zx, r), newAxis(zy, r)
		e.t, e.hasT = f.T, true
		return 0
	}
	// The gap closed inside the gap window, so the filter integrates it: drop the buffer.
	e.pendingStepM = 0
	dt := f.T - e.t
	e.t = f.T
	e.x.predict(dt)
	e.y.predict(dt)
	e.x.updatePos(zx, r)
	e.y.updatePos(zy, r)

	var doppler *float64
	if validPtr(f.SpeedMps) && *f.SpeedMps >= 0 && *f.SpeedMps <= e.MaxSpeedMps {
		sa := DefaultSpeedSigmaMps
		if validPtr(f.SpeedAccuracyMps) && *f.SpeedAccuracyMps > 0 {
			sa = *f.SpeedAccuracyMps
		}
		if sa <= MaxSpeedSigmaMps {
			sp := *f.SpeedMps
			doppler = &sp
			if validPtr(f.BearingDeg) && sp >= StationarySpeedMps {
				rv := math.Pow(math.Max(sa, MinSpeedSigmaMps), 2)
				b := radians(*f.BearingDeg)
				e.x.updateVel(sp*math.Sin(b), rv)
				e.y.updateVel(sp*math.Cos(b), rv)
			}
		}
	}

	var speed, floor float64
	if doppler != nil {
		speed, floor = *doppler, StationarySpeedMps
	} else {
		speed, floor = math.Hypot(e.x.v, e.y.v), PosOnlyStationarySpeedMps
	}
	if speed < floor {
		return 0
	}
	inc := math.Min(speed, e.MaxSpeedMps) * dt
	e.GpsDistanceM += inc
	e.winM += inc
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
