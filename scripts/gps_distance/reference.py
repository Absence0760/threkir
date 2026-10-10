"""GPS distance estimator — reference implementation, spec v1.3.

Every port (Dart, TypeScript, Deno, Kotlin, Swift, Rust, Go) must reproduce
gps_distance_vectors.json to 1e-3 m. Operation order matters only at the
1e-9 level; keep formulas as written. Scalar float64 arithmetic only, no
library beyond sqrt / hypot / sin / cos / exp / radians / degrees.

Two entry points:
  GpsDistanceEstimator  the forward (causal) filter every live screen runs.
  smooth_distance       the saved / recomputed figure: a forward pass plus a
                        Rauch-Tung-Striebel backward pass over the whole run.
"""
import math

SPEC_VERSION = "1.3"

EARTH_RADIUS_M = 6371008.8
Q_ACCEL = 0.6                     # m^2/s^3, white-acceleration spectral density (unvalidated, see doc)
MIN_POS_SIGMA_M = 3.0             # floor on horizontal accuracy (and on the adapted sigma)
INIT_VEL_VAR = 25.0               # (m/s)^2 initial velocity variance
MIN_SPEED_SIGMA_MPS = 0.3         # floor on Doppler speed accuracy
DEFAULT_SPEED_SIGMA_MPS = 0.5     # used when the platform reports none
MAX_SPEED_SIGMA_MPS = 1.5         # Doppler worse than this is ignored
STATIONARY_SPEED_MPS = 0.4        # below: no distance (Doppler present)
POS_ONLY_STATIONARY_SPEED_MPS = 0.8  # below: no distance (no Doppler)
GAP_S = 10.0                      # fix interval above this (x expected interval) re-anchors, no credit
FRESH_FIX_S = 2.0                 # a fix this recent (x expected interval) counts as "GPS good" for stride learning
STRIDE_WINDOW_STEPS = 50
MIN_STRIDE_M, MAX_STRIDE_M = 0.4, 2.5
STRIDE_EMA_ALPHA = 0.2

# v1.2 — innovation gate (2-D Mahalanobis, chi-square 2 dof at p = 0.001).
GATE_CHI2 = 13.8155
GATE_MAX_REJECTS = 5              # this many consecutive rejections: the next rejected fix re-anchors position
# v1.2 — adaptive measurement noise (covariance matching on accepted innovations).
R_SCALE_ALPHA = 0.05
R_SCALE_MIN, R_SCALE_MAX = 1.0, 9.0
# v1.2 — Doppler-vs-position cross-check.
XCHECK_TAU_S = 60.0               # EMA time constant of both speeds
XCHECK_MIN_S = 120.0              # compared seconds before the first verdict
XCHECK_ENTER_ABS_MPS, XCHECK_ENTER_REL = 0.4, 0.15
XCHECK_EXIT_ABS_MPS, XCHECK_EXIT_REL = 0.2, 0.08
XCHECK_PERSIST_S = 60.0           # a verdict flips only after disagreeing (or agreeing) this long
XCHECK_MAX_SPAN_S = 5.0           # longer fix-to-fix spans cut corners, so they are not compared
# v1.2 — Doppler low-speed debias.
DEBIAS_FULL_MPS, DEBIAS_ZERO_MPS = 0.5, 1.0
# v1.3 — Doppler speed scale. Phones carry a slowly varying Doppler speed bias of
# several percent (2026-10-09, against a Garmin on the same course: an iPhone 7% low,
# a fused-provider Android 10% high and then low within one run), far below the
# cross-check's threshold, and the filter credits distance from Doppler speed. The
# constants are tuned against that watch, not a measured course (issue #1090 item 2).
DSCALE_TAU_S = 600.0              # exponential forgetting time of both integrals
DSCALE_MIN_S = 60.0               # compared seconds before the scale leaves 1
DSCALE_MIN, DSCALE_MAX = 0.8, 1.25
DSCALE_MIN_SPEED_MPS = 1.5        # both ends' Doppler; below it, keeping only high readings biases the scale low
DSCALE_MAX_TURN_DEG = 45.0        # bearing change across the span; a chord across a turn is shorter than the arc
# v1.2 — pedometer zero-velocity update. ZUPT_NO_STEP_S must be measured on device.
ZUPT_NO_STEP_S = 6.0
ZUPT_VEL_SIGMA_MPS = 0.1
ZUPT_DOPPLER_OVERRIDE_MPS = 1.0
ZUPT_RELEASE_M = 40.0
# v1.2 — post-hoc stop detection for tracks with no Doppler (smoother only).
STOP_HALF_WINDOW_S = 20.0
STOP_MIN_HALF_FIXES = 3
STOP_SPEED_MPS = 0.5
STOP_RADIUS_M = 10.0


def _valid(x):
    return x is not None and math.isfinite(x)


def _wrap_lng(d):
    """Wrap a longitude difference (inputs within [-180, 180]) into [-180, 180)."""
    if d >= 180.0:
        return d - 360.0
    if d < -180.0:
        return d + 360.0
    return d


def _doppler_speed(speed_mps, speed_accuracy_mps, max_speed_mps):
    """Usable, debiased Doppler speed, or None. Returns (speed, sigma)."""
    if not (_valid(speed_mps) and 0.0 <= speed_mps <= max_speed_mps):
        return None, None
    reported = _valid(speed_accuracy_mps) and speed_accuracy_mps > 0
    sa = speed_accuracy_mps if reported else DEFAULT_SPEED_SIGMA_MPS
    if sa > MAX_SPEED_SIGMA_MPS:
        return None, None
    s = speed_mps
    if reported and s < DEBIAS_ZERO_MPS:
        w = 1.0 if s <= DEBIAS_FULL_MPS else (DEBIAS_ZERO_MPS - s) / (DEBIAS_ZERO_MPS - DEBIAS_FULL_MPS)
        s = math.sqrt(max(0.0, s * s - w * sa * sa))
    return s, sa


class _Axis:
    """1-D constant-velocity Kalman filter: state [p, v], covariance [[a,b],[b,c]]."""

    def __init__(self, p, pos_var):
        self.p, self.v = p, 0.0
        self.a, self.b, self.c = pos_var, 0.0, INIT_VEL_VAR

    def predict(self, dt):
        self.p += self.v * dt
        a = self.a + 2.0 * dt * self.b + dt * dt * self.c + Q_ACCEL * dt ** 3 / 3.0
        b = self.b + dt * self.c + Q_ACCEL * dt * dt / 2.0
        c = self.c + Q_ACCEL * dt
        self.a, self.b, self.c = a, b, c

    def update_pos(self, z, r):
        s = self.a + r
        k0, k1 = self.a / s, self.b / s
        y = z - self.p
        self.p += k0 * y
        self.v += k1 * y
        a, b, c = self.a, self.b, self.c
        self.a, self.b, self.c = (1 - k0) * a, (1 - k0) * b, c - k1 * b

    def update_vel(self, z, r):
        s = self.c + r
        k0, k1 = self.b / s, self.c / s
        y = z - self.v
        self.p += k0 * y
        self.v += k1 * y
        a, b, c = self.a, self.b, self.c
        self.a, self.b, self.c = a - k0 * b, (1 - k1) * b, (1 - k1) * c

    def reset_pos(self, z, r):
        """Lock-out re-anchor: position jumps to z, velocity is kept."""
        self.p, self.a, self.b = z, r, 0.0

    def state(self):
        return (self.p, self.v, self.a, self.b, self.c)


class GpsDistanceEstimator:
    def __init__(self, max_speed_mps=10.0, expected_interval_s=1.0, initial_stride_m=None, record=False):
        self.max_speed_mps = max_speed_mps
        scale = expected_interval_s if (_valid(expected_interval_s) and expected_interval_s > 1.0) else 1.0
        self._gap_s = GAP_S * scale
        self._fresh_fix_s = FRESH_FIX_S * scale
        self.gps_distance_m = 0.0
        self.step_distance_m = 0.0
        self.stride_m = initial_stride_m if (_valid(initial_stride_m) and
                                              MIN_STRIDE_M <= initial_stride_m <= MAX_STRIDE_M) else None
        self._lat0 = self._lng0 = None
        self._x = self._y = None          # main filter (Doppler-fused)
        self._t = None
        self._win_steps = 0
        self._win_m = 0.0
        self._last_steps = None
        self._last_step_t = None
        self._pending_step_m = 0.0
        # v1.2 state
        self.r_scale = 1.0
        self.rejected_fixes = 0
        self._reject_streak = 0
        self.doppler_trusted = True
        self._xc_doppler = self._xc_pos = 0.0
        self._xc_time = 0.0
        self._xc_persist_s = 0.0
        self._xc_last = None              # (x, y, t) of the last fix whose position the filter took
        # v1.3 state
        self.doppler_scale = 1.0
        self._ds_pos = self._ds_dop = 0.0
        self._ds_time = 0.0
        self._ds_last = None              # (x, y, t, dop, bearing) of the last fix whose position the filter took
        self._steps_seen = False
        self._last_step_inc_t = None
        self._zupt_released = False
        self._zupt_anchor = None
        self.zupt_fixes = 0
        self.records = [] if record else None

    @property
    def distance_m(self):
        return self.gps_distance_m + self.step_distance_m

    def _project(self, lat, lng):
        x = math.radians(_wrap_lng(lng - self._lng0)) * EARTH_RADIUS_M * math.cos(math.radians(self._lat0))
        y = math.radians(lat - self._lat0) * EARTH_RADIUS_M
        return x, y

    def unproject(self, x, y):
        lat = self._lat0 + math.degrees(y / EARTH_RADIUS_M)
        lng = self._lng0 + math.degrees(x / (EARTH_RADIUS_M * math.cos(math.radians(self._lat0))))
        return lat, _wrap_lng(lng)

    def _zupt_due(self, t, dop):
        """Pedometer says stationary: steps seen this run, none for ZUPT_NO_STEP_S, Doppler not contradicting."""
        if not self._steps_seen or self._zupt_released or t - self._last_step_inc_t <= ZUPT_NO_STEP_S:
            return False
        return not (dop is not None and self.doppler_trusted and dop >= ZUPT_DOPPLER_OVERRIDE_MPS)

    def _record(self, **kw):
        if self.records is not None:
            kw["x"], kw["y"] = self._x.state(), self._y.state()
            kw["step_distance_m"] = self.step_distance_m
            self.records.append(kw)

    def add_fix(self, t, lat, lng, accuracy_m=None, speed_mps=None,
                speed_accuracy_mps=None, bearing_deg=None, stopped_hint=False):
        """t: seconds on a clock monotonic within the run. Returns metres credited.
        stopped_hint: the caller knows the runner is stationary (post-hoc stop detection)."""
        if not (_valid(t) and _valid(lat) and _valid(lng)):
            return 0.0
        if self._lat0 is None:
            self._lat0, self._lng0 = lat, lng
        zx, zy = self._project(lat, lng)
        sigma = accuracy_m if (_valid(accuracy_m) and accuracy_m > 0) else MIN_POS_SIGMA_M
        r_stated = max(sigma, MIN_POS_SIGMA_M) ** 2
        r = max(r_stated * self.r_scale, MIN_POS_SIGMA_M ** 2)
        if self._t is not None and t <= self._t:
            return 0.0
        dop, sa = _doppler_speed(speed_mps, speed_accuracy_mps, self.max_speed_mps)
        if self._t is None or t - self._t > self._gap_s:
            # (Re-)anchor. Steps buffered across a real gap are committed now.
            if self._t is not None:
                self.step_distance_m += self._pending_step_m
            self._pending_step_m = 0.0
            self._x, self._y = _Axis(zx, r), _Axis(zy, r)
            self._t = t
            self._xc_last = (zx, zy, t)
            self._ds_last = (zx, zy, t, dop, bearing_deg)
            self._reject_streak = 0
            self._zupt_anchor = None
            zupt = stopped_hint or self._zupt_due(t, dop)
            self._record(t=t, anchor=True, chain_break=True, dt=0.0, pred=None,
                         zupt=zupt, dop=dop * self.doppler_scale if (dop is not None and self.doppler_trusted) else None,
                         chord=None)
            return 0.0
        # The gap closed inside the gap window, so the filter integrates it: drop the buffer.
        self._pending_step_m = 0.0
        dt = t - self._t
        self._t = t
        self._x.predict(dt)
        self._y.predict(dt)
        pred = (self._x.state(), self._y.state())

        # 1. Innovation gate on the main filter's predicted position.
        yx, yy = zx - self._x.p, zy - self._y.p
        ax_, ay_ = self._x.a, self._y.a
        nis = yx * yx / (ax_ + r) + yy * yy / (ay_ + r)
        chain_break = False
        accepted = nis <= GATE_CHI2
        if accepted:
            self._reject_streak = 0
            self._x.update_pos(zx, r)
            self._y.update_pos(zy, r)
            # 2. Adaptive R: covariance matching, sample clamped, EMA, bounded.
            sample = ((yx * yx - ax_) + (yy * yy - ay_)) / (2.0 * r_stated)
            sample = min(max(sample, 0.0), R_SCALE_MAX)
            ema = (1.0 - R_SCALE_ALPHA) * self.r_scale + R_SCALE_ALPHA * sample
            self.r_scale = min(max(ema, R_SCALE_MIN), R_SCALE_MAX)
        else:
            self.rejected_fixes += 1
            self._reject_streak += 1
            if self._reject_streak > GATE_MAX_REJECTS:
                self._x.reset_pos(zx, r)
                self._y.reset_pos(zy, r)
                self._reject_streak = 0
                self._xc_last = (zx, zy, t)
                self._ds_last = (zx, zy, t, dop, bearing_deg)
                chain_break = True

        # 3. Zero-velocity update (pedometer, or the caller's stop hint).
        ped_zupt = self._zupt_due(t, dop)
        chord = None
        if ped_zupt:
            if self._zupt_anchor is None:
                self._zupt_anchor = (self._x.p, self._y.p)
            else:
                moved = math.hypot(self._x.p - self._zupt_anchor[0], self._y.p - self._zupt_anchor[1])
                if moved > ZUPT_RELEASE_M:
                    # The pedometer stalled while the runner moved: stop trusting it until it counts again.
                    self._zupt_released = True
                    self._zupt_anchor = None
                    ped_zupt = False
                    chord = moved
        else:
            self._zupt_anchor = None
        zupt = stopped_hint or ped_zupt
        if zupt:
            chord = None
            self.zupt_fixes += 1
            rz = ZUPT_VEL_SIGMA_MPS ** 2
            self._x.update_vel(0.0, rz)
            self._y.update_vel(0.0, rz)

        # 4. Doppler-vs-position cross-check: Doppler speed against the raw fixes'
        #    displacement projected on the Doppler bearing (unbiased on turns, unlike a
        #    filtered speed, which cuts corners).
        if accepted:
            lx, ly, lt = self._xc_last
            span = t - lt
            if (dop is not None and not zupt and _valid(bearing_deg)
                    and dop >= POS_ONLY_STATIONARY_SPEED_MPS and span <= XCHECK_MAX_SPAN_S):
                b = math.radians(bearing_deg)
                u = ((zx - lx) * math.sin(b) + (zy - ly) * math.cos(b)) / span
                if self._xc_time == 0.0:
                    self._xc_doppler = self._xc_pos = dop
                else:
                    alpha = min(1.0, span / XCHECK_TAU_S)
                    self._xc_doppler += alpha * (dop - self._xc_doppler)
                    self._xc_pos += alpha * (u - self._xc_pos)
                self._xc_time += span
                if self._xc_time >= XCHECK_MIN_S:
                    diff = abs(self._xc_doppler - self._xc_pos)
                    ref_speed = abs(self._xc_pos)
                    if self.doppler_trusted:
                        flip = diff > max(XCHECK_ENTER_ABS_MPS, XCHECK_ENTER_REL * ref_speed)
                    else:
                        flip = diff < max(XCHECK_EXIT_ABS_MPS, XCHECK_EXIT_REL * ref_speed)
                    self._xc_persist_s = self._xc_persist_s + span if flip else 0.0
                    if self._xc_persist_s >= XCHECK_PERSIST_S:
                        self.doppler_trusted = not self.doppler_trusted
                        self._xc_persist_s = 0.0
            self._xc_last = (zx, zy, t)

            # 4b. Doppler scale (v1.3): the ratio of exponentially forgotten integrals of
            #     the fixes' displacement along the span's mean Doppler bearing and of the
            #     trapezoid Doppler distance over the same span. Position noise averages
            #     out of a sum of displacements, where it does not out of a sum of hop lengths.
            lx, ly, lt, ldop, lb = self._ds_last
            span = t - lt
            turn = abs(bearing_deg - lb) % 360.0 if (_valid(bearing_deg) and _valid(lb)) else None
            if (not zupt and dop is not None and ldop is not None and turn is not None
                    and dop >= DSCALE_MIN_SPEED_MPS and ldop >= DSCALE_MIN_SPEED_MPS
                    and span <= XCHECK_MAX_SPAN_S and min(turn, 360.0 - turn) <= DSCALE_MAX_TURN_DEG):
                b0, b1 = math.radians(lb), math.radians(bearing_deg)
                ux, uy = math.sin(b0) + math.sin(b1), math.cos(b0) + math.cos(b1)
                n = math.hypot(ux, uy)
                w = math.exp(-span / DSCALE_TAU_S)
                self._ds_pos = w * self._ds_pos + ((zx - lx) * ux + (zy - ly) * uy) / n
                self._ds_dop = w * self._ds_dop + 0.5 * (ldop + dop) * span
                self._ds_time += span
                if self._ds_time >= DSCALE_MIN_S and self._ds_dop > 0.0:
                    self.doppler_scale = min(max(self._ds_pos / self._ds_dop, DSCALE_MIN), DSCALE_MAX)
            self._ds_last = (zx, zy, t, dop, bearing_deg)

        # 5. Doppler velocity update.
        use_dop = dop * self.doppler_scale if (dop is not None and self.doppler_trusted) else None
        if use_dop is not None and not zupt and _valid(bearing_deg) and use_dop >= STATIONARY_SPEED_MPS:
            rv = max(sa, MIN_SPEED_SIGMA_MPS) ** 2
            b = math.radians(bearing_deg)
            self._x.update_vel(use_dop * math.sin(b), rv)
            self._y.update_vel(use_dop * math.cos(b), rv)

        # 6. Credit.
        if chord is not None:
            inc = chord
        elif zupt:
            inc = 0.0
        else:
            if use_dop is not None:
                speed, floor = use_dop, STATIONARY_SPEED_MPS
            else:
                speed, floor = math.hypot(self._x.v, self._y.v), POS_ONLY_STATIONARY_SPEED_MPS
            inc = 0.0 if speed < floor else min(speed, self.max_speed_mps) * dt
        self.gps_distance_m += inc
        self._win_m += inc
        self._record(t=t, anchor=False, chain_break=chain_break, dt=dt, pred=pred,
                     zupt=zupt, dop=use_dop, chord=chord)
        return inc

    def add_steps(self, t, cumulative_steps):
        """Cumulative pedometer count. Learns stride while GPS is good; buffers
        steps x stride while it is not (committed only if the gap exceeds the gap window)."""
        if not _valid(t) or cumulative_steps is None:
            return
        prev, prev_t = self._last_steps, self._last_step_t
        self._last_steps, self._last_step_t = cumulative_steps, t
        if prev is None or cumulative_steps < prev or prev_t is None or t <= prev_t:
            return
        d = cumulative_steps - prev
        if d > 0:
            self._steps_seen = True
            self._last_step_inc_t = t
            self._zupt_released = False
        if self._t is not None and t - self._t <= self._fresh_fix_s:
            self._win_steps += d
            if self._win_steps >= STRIDE_WINDOW_STEPS:
                stride = self._win_m / self._win_steps
                if MIN_STRIDE_M <= stride <= MAX_STRIDE_M:
                    self.stride_m = stride if self.stride_m is None else \
                        (1 - STRIDE_EMA_ALPHA) * self.stride_m + STRIDE_EMA_ALPHA * stride
                self._win_steps, self._win_m = 0, 0.0
            return
        self._win_steps, self._win_m = 0, 0.0
        if self.stride_m is None:
            return
        self._pending_step_m += min(d * self.stride_m, self.max_speed_mps * (t - prev_t))

    def finish(self, t):
        """End of run: commit buffered steps if the trailing gap exceeds the gap window."""
        if self._t is not None and _valid(t) and t - self._t > self._gap_s:
            self.step_distance_m += self._pending_step_m
        self._pending_step_m = 0.0


def detect_stops(fixes, expected_interval_s=1.0):
    """Post-hoc stop flags for a track with no Doppler. fixes: [(t, x, y)] in
    strictly increasing t. Fix j is stopped when both half-windows around it hold
    >= STOP_MIN_HALF_FIXES fixes, the net speed between the halves' mean positions
    is < STOP_SPEED_MPS, and the RMS distance of the whole window from its mean is
    < STOP_RADIUS_M."""
    scale = expected_interval_s if (_valid(expected_interval_s) and expected_interval_s > 1.0) else 1.0
    half = STOP_HALF_WINDOW_S * scale
    n = len(fixes)
    out = [False] * n
    lo = 0
    hi = 0
    for j in range(n):
        tj = fixes[j][0]
        while fixes[lo][0] < tj - half:
            lo += 1
        while hi + 1 < n and fixes[hi + 1][0] <= tj + half:
            hi += 1
        na, nb = j - lo, hi - j + 1
        if na < STOP_MIN_HALF_FIXES or nb < STOP_MIN_HALF_FIXES:
            continue
        ta = xa = ya = 0.0
        for k in range(lo, j):
            ta += fixes[k][0]; xa += fixes[k][1]; ya += fixes[k][2]
        tb = xb = yb = 0.0
        for k in range(j, hi + 1):
            tb += fixes[k][0]; xb += fixes[k][1]; yb += fixes[k][2]
        net = math.hypot(xb / nb - xa / na, yb / nb - ya / na) / (tb / nb - ta / na)
        if net >= STOP_SPEED_MPS:
            continue
        mx, my = (xa + xb) / (na + nb), (ya + yb) / (na + nb)
        ss = 0.0
        for k in range(lo, hi + 1):
            dx, dy = fixes[k][1] - mx, fixes[k][2] - my
            ss += dx * dx + dy * dy
        out[j] = math.sqrt(ss / (na + nb)) < STOP_RADIUS_M
    return out


def _rts(records, s, e, axis):
    """RTS backward pass over records[s..e] (one unbroken chain) for one axis.
    Returns smoothed (p, v) per record."""
    pf = [r[axis] for r in records[s:e + 1]]
    out = [None] * (e - s + 1)
    out[-1] = (pf[-1][0], pf[-1][1])
    for k in range(e - s - 1, -1, -1):
        p, v, a, b, c = pf[k]
        nxt = records[s + k + 1]
        dt = nxt["dt"]
        pp, pv, A, B, C = nxt["pred"][0 if axis == "x" else 1]
        det = A * C - B * B
        g00 = ((a + dt * b) * C - b * B) / det
        g01 = (b * A - (a + dt * b) * B) / det
        g10 = ((b + dt * c) * C - c * B) / det
        g11 = (c * A - (b + dt * c) * B) / det
        dp = out[k + 1][0] - pp
        dv = out[k + 1][1] - pv
        out[k] = (p + g00 * dp + g01 * dv, v + g10 * dp + g11 * dv)
    return out


def smooth_distance(events, max_speed_mps=10.0, expected_interval_s=1.0, initial_stride_m=None):
    """Saved / recomputed distance. events: dicts {"type": "fix", t, lat, lng, acc,
    speed, speedAcc, bearing} | {"type": "steps", t, count} | {"type": "finish", t},
    in arrival order. Returns a dict:
      distance_m, gps_distance_m, step_distance_m,
      cumulative_m  per event: smoothed GPS credit through that event + step distance committed by then,
      positions     per event: (lat, lng) of the smoothed position for an accepted fix, else None,
      stopped_fixes how many fixes post-hoc stop detection flagged."""
    # Accepted fixes exactly as the estimator would accept them.
    kept = []
    lat0 = lng0 = None
    last_t = None
    has_doppler = False
    for i, ev in enumerate(events):
        if ev["type"] != "fix":
            continue
        t, lat, lng = ev["t"], ev["lat"], ev["lng"]
        if not (_valid(t) and _valid(lat) and _valid(lng)):
            continue
        if lat0 is None:
            lat0, lng0 = lat, lng
        if last_t is not None and t <= last_t:
            continue
        last_t = t
        if _valid(ev.get("speed")):
            has_doppler = True
        x = math.radians(_wrap_lng(lng - lng0)) * EARTH_RADIUS_M * math.cos(math.radians(lat0))
        y = math.radians(lat - lat0) * EARTH_RADIUS_M
        kept.append((i, t, x, y))
    hints = set()
    if not has_doppler:
        flags = detect_stops([(t, x, y) for _, t, x, y in kept], expected_interval_s)
        hints = {kept[j][0] for j, f in enumerate(flags) if f}

    est = GpsDistanceEstimator(max_speed_mps, expected_interval_s, initial_stride_m, record=True)
    rec_event = []
    for i, ev in enumerate(events):
        if ev["type"] == "fix":
            n = len(est.records)
            est.add_fix(ev["t"], ev["lat"], ev["lng"], ev.get("acc"), ev.get("speed"),
                        ev.get("speedAcc"), ev.get("bearing"), stopped_hint=i in hints)
            if len(est.records) > n:
                rec_event.append(i)
        elif ev["type"] == "steps":
            est.add_steps(ev["t"], ev["count"])
        else:
            est.finish(ev["t"])
    recs = est.records

    # Backward pass per unbroken chain (a gap re-anchor or a gate lock-out starts a new one).
    sm = [None] * len(recs)
    s = 0
    for k in range(1, len(recs) + 1):
        if k == len(recs) or recs[k]["chain_break"]:
            xs, ys = _rts(recs, s, k - 1, "x"), _rts(recs, s, k - 1, "y")
            for j in range(s, k):
                sm[j] = (xs[j - s][0], ys[j - s][0], xs[j - s][1], ys[j - s][1])
            s = k

    # Credit along the smoothed velocities: trapezoid per interval, gap re-anchors not credited.
    def eff(k):
        r = recs[k]
        if r["zupt"]:
            return 0.0
        if r["dop"] is not None:
            speed, floor = r["dop"], STATIONARY_SPEED_MPS
        else:
            speed, floor = math.hypot(sm[k][2], sm[k][3]), POS_ONLY_STATIONARY_SPEED_MPS
        return 0.0 if speed < floor else min(speed, max_speed_mps)

    effs = [eff(k) for k in range(len(recs))]
    credit = [0.0] * len(recs)
    for k in range(len(recs)):
        r = recs[k]
        if r["anchor"]:
            continue
        credit[k] = r["chord"] if r["chord"] is not None else 0.5 * (effs[k - 1] + effs[k]) * r["dt"]

    by_event = {e: k for k, e in enumerate(rec_event)}
    cumulative, positions = [], []
    gps = 0.0
    step_m = 0.0
    for i, ev in enumerate(events):
        k = by_event.get(i)
        pos = None
        if k is not None:
            gps += credit[k]
            step_m = recs[k]["step_distance_m"]
            pos = est.unproject(sm[k][0], sm[k][1])
        elif ev["type"] == "finish":
            step_m = est.step_distance_m
        cumulative.append(gps + step_m)
        positions.append(pos)
    return {"distance_m": gps + est.step_distance_m, "gps_distance_m": gps,
            "step_distance_m": est.step_distance_m, "cumulative_m": cumulative,
            "positions": positions, "stopped_fixes": len(hints)}
