package gpsdistance

import "math"

// EventKind tells SmoothDistance what an Event carries.
type EventKind int

const (
	EventFix EventKind = iota
	EventSteps
	EventFinish
)

// Event is one entry of a run's event stream, in arrival order. A fix
// event carries Fix (its StoppedHint is ignored: SmoothDistance derives
// its own); a steps event carries T and Steps (the cumulative count); a
// finish event carries T.
type Event struct {
	Kind  EventKind
	Fix   Fix
	T     float64
	Steps int
}

// LatLng is a position in degrees.
type LatLng struct{ Lat, Lng float64 }

// SmoothResult is SmoothDistance's output. CumulativeM and Positions have
// one entry per input event; Positions is nil for a steps / finish event
// and for an ignored fix.
type SmoothResult struct {
	DistanceM     float64
	GpsDistanceM  float64
	StepDistanceM float64
	CumulativeM   []float64
	Positions     []*LatLng
	StoppedFixes  int
}

// StopFix is one accepted fix in the local plane, for DetectStops.
type StopFix struct{ T, X, Y float64 }

// DetectStops flags stationary fixes on a track with no Doppler. fixes
// must be in strictly increasing T. Fix j is stopped when both
// half-windows around it hold at least StopMinHalfFixes fixes, the net
// speed between the halves' mean positions is below StopSpeedMps, and the
// RMS distance of the whole window from its mean is below StopRadiusM.
func DetectStops(fixes []StopFix, expectedIntervalS float64) []bool {
	half := StopHalfWindowS * intervalScale(expectedIntervalS)
	n := len(fixes)
	out := make([]bool, n)
	lo, hi := 0, 0
	for j := 0; j < n; j++ {
		tj := fixes[j].T
		for fixes[lo].T < tj-half {
			lo++
		}
		for hi+1 < n && fixes[hi+1].T <= tj+half {
			hi++
		}
		na, nb := j-lo, hi-j+1
		if na < StopMinHalfFixes || nb < StopMinHalfFixes {
			continue
		}
		var ta, xa, ya float64
		for k := lo; k < j; k++ {
			ta += fixes[k].T
			xa += fixes[k].X
			ya += fixes[k].Y
		}
		var tb, xb, yb float64
		for k := j; k <= hi; k++ {
			tb += fixes[k].T
			xb += fixes[k].X
			yb += fixes[k].Y
		}
		fa, fb := float64(na), float64(nb)
		net := math.Hypot(xb/fb-xa/fa, yb/fb-ya/fa) / (tb/fb - ta/fa)
		if net >= StopSpeedMps {
			continue
		}
		mx, my := (xa+xb)/(fa+fb), (ya+yb)/(fa+fb)
		var ss float64
		for k := lo; k <= hi; k++ {
			dx, dy := fixes[k].X-mx, fixes[k].Y-my
			ss += dx*dx + dy*dy
		}
		out[j] = math.Sqrt(ss/(fa+fb)) < StopRadiusM
	}
	return out
}

// rts is the Rauch-Tung-Striebel backward pass over recs[s..e] (one
// unbroken chain) for one axis; it returns the smoothed (p, v) per record.
func rts(recs []record, s, e int, useX bool) [][2]float64 {
	filt := func(r record) axisState {
		if useX {
			return r.x
		}
		return r.y
	}
	pred := func(r record) axisState {
		if useX {
			return r.predX
		}
		return r.predY
	}
	out := make([][2]float64, e-s+1)
	last := filt(recs[e])
	out[e-s] = [2]float64{last.p, last.v}
	for k := e - s - 1; k >= 0; k-- {
		f := filt(recs[s+k])
		nxt := recs[s+k+1]
		dt := nxt.dt
		pp := pred(nxt)
		A, B, C := pp.a, pp.b, pp.c
		det := A*C - B*B
		g00 := ((f.a+dt*f.b)*C - f.b*B) / det
		g01 := (f.b*A - (f.a+dt*f.b)*B) / det
		g10 := ((f.b+dt*f.c)*C - f.c*B) / det
		g11 := (f.c*A - (f.b+dt*f.c)*B) / det
		dp := out[k+1][0] - pp.p
		dv := out[k+1][1] - pp.v
		out[k] = [2]float64{f.p + g00*dp + g01*dv, f.v + g10*dp + g11*dv}
	}
	return out
}

// SmoothDistance is the saved / recomputed distance: a forward pass plus
// a Rauch-Tung-Striebel backward pass over the whole run, with post-hoc
// stop detection when no accepted fix carries Doppler speed.
func SmoothDistance(events []Event, o Options) SmoothResult {
	// Accepted fixes exactly as the estimator would accept them.
	type kept struct {
		event int
		fix   StopFix
	}
	var ks []kept
	var lat0, lng0, lastT float64
	haveOrigin, haveT, hasDoppler := false, false, false
	for i, ev := range events {
		if ev.Kind != EventFix {
			continue
		}
		f := ev.Fix
		if !(finite(f.T) && finite(f.Lat) && finite(f.Lng)) {
			continue
		}
		if !haveOrigin {
			lat0, lng0, haveOrigin = f.Lat, f.Lng, true
		}
		if haveT && f.T <= lastT {
			continue
		}
		lastT, haveT = f.T, true
		if validPtr(f.SpeedMps) {
			hasDoppler = true
		}
		x := radians(wrapLng(f.Lng-lng0)) * EarthRadiusM * math.Cos(radians(lat0))
		y := radians(f.Lat-lat0) * EarthRadiusM
		ks = append(ks, kept{i, StopFix{f.T, x, y}})
	}
	hints := map[int]bool{}
	if !hasDoppler {
		sf := make([]StopFix, len(ks))
		for j, k := range ks {
			sf[j] = k.fix
		}
		for j, stopped := range DetectStops(sf, o.ExpectedIntervalS) {
			if stopped {
				hints[ks[j].event] = true
			}
		}
	}

	est := NewWithOptions(o)
	est.recording = true
	recEvent := map[int]int{}
	for i, ev := range events {
		switch ev.Kind {
		case EventFix:
			n := len(est.records)
			f := ev.Fix
			f.StoppedHint = hints[i]
			est.AddFix(f)
			if len(est.records) > n {
				recEvent[i] = n
			}
		case EventSteps:
			est.AddSteps(ev.T, ev.Steps)
		case EventFinish:
			est.Finish(ev.T)
		}
	}
	recs := est.records

	// Backward pass per unbroken chain (a gap re-anchor or a gate lock-out starts a new one).
	type smoothed struct{ px, py, vx, vy float64 }
	sm := make([]smoothed, len(recs))
	s := 0
	for k := 1; k <= len(recs); k++ {
		if k == len(recs) || recs[k].chainBreak {
			xs, ys := rts(recs, s, k-1, true), rts(recs, s, k-1, false)
			for j := s; j < k; j++ {
				sm[j] = smoothed{xs[j-s][0], ys[j-s][0], xs[j-s][1], ys[j-s][1]}
			}
			s = k
		}
	}

	// Credit along the smoothed velocities: trapezoid per interval, gap re-anchors not credited.
	effs := make([]float64, len(recs))
	for k, r := range recs {
		if r.zupt {
			continue
		}
		speed, floor := math.Hypot(sm[k].vx, sm[k].vy), PosOnlyStationarySpeedMps
		if r.hasDop {
			speed, floor = r.dop, StationarySpeedMps
		}
		if speed >= floor {
			effs[k] = math.Min(speed, est.MaxSpeedMps)
		}
	}
	credit := make([]float64, len(recs))
	for k, r := range recs {
		switch {
		case r.anchor:
		case r.hasChord:
			credit[k] = r.chord
		default:
			credit[k] = 0.5 * (effs[k-1] + effs[k]) * r.dt
		}
	}

	out := SmoothResult{
		CumulativeM:  make([]float64, len(events)),
		Positions:    make([]*LatLng, len(events)),
		StoppedFixes: len(hints),
	}
	var gps, stepM float64
	for i, ev := range events {
		if k, ok := recEvent[i]; ok {
			gps += credit[k]
			stepM = recs[k].stepDistanceM
			lat, lng := est.Unproject(sm[k].px, sm[k].py)
			out.Positions[i] = &LatLng{lat, lng}
		} else if ev.Kind == EventFinish {
			stepM = est.StepDistanceM
		}
		out.CumulativeM[i] = gps + stepM
	}
	out.GpsDistanceM = gps
	out.StepDistanceM = est.StepDistanceM
	out.DistanceM = gps + est.StepDistanceM
	return out
}
