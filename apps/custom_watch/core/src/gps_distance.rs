//! GPS distance estimator, spec v1.2 forward filter — the `no_std` port of
//! `scripts/gps_distance/reference.py` (docs/features/gps_distance.md). The
//! spec's smoother needs the whole run in memory and is not ported here; the
//! phone or server re-derives a saved figure from the uploaded track.
//!
//! Summing the straight hop between consecutive raw fixes inflates distance
//! at running pace, because a 1 Hz fix moves about as far as its own error and
//! every zig-zag across the true line adds length. This filters position with
//! two constant-velocity Kalman filters on a local tangent plane, credits the
//! receiver's Doppler speed over ground when it is usable, refuses to credit
//! anything below a stationary floor, and re-anchors across a gap rather than
//! inventing the un-sampled ground. v1.2 adds an innovation gate with a
//! lock-out re-anchor, adaptive measurement noise, a Doppler-vs-position
//! cross-check, a low-speed Doppler debias, a pedometer zero-velocity update
//! and an antimeridian-safe projection.
//!
//! Every port replays `fixtures/gps_distance_vectors.json` to 1e-3 m, so the
//! arithmetic follows the reference operation for operation. Fixed-size, no
//! heap. A constant changed here alone fails the vectors, which is the point.

pub const EARTH_RADIUS_M: f64 = 6_371_008.8;
pub const Q_ACCEL: f64 = 0.6;
pub const MIN_POS_SIGMA_M: f64 = 3.0;
pub const INIT_VEL_VAR: f64 = 25.0;
pub const MIN_SPEED_SIGMA_MPS: f64 = 0.3;
pub const DEFAULT_SPEED_SIGMA_MPS: f64 = 0.5;
pub const MAX_SPEED_SIGMA_MPS: f64 = 1.5;
pub const STATIONARY_SPEED_MPS: f64 = 0.4;
pub const POS_ONLY_STATIONARY_SPEED_MPS: f64 = 0.8;
pub const GAP_S: f64 = 10.0;
pub const FRESH_FIX_S: f64 = 2.0;
pub const STRIDE_WINDOW_STEPS: i64 = 50;
pub const MIN_STRIDE_M: f64 = 0.4;
pub const MAX_STRIDE_M: f64 = 2.5;
pub const STRIDE_EMA_ALPHA: f64 = 0.2;
pub const GATE_CHI2: f64 = 13.8155;
pub const GATE_MAX_REJECTS: u32 = 5;
pub const R_SCALE_ALPHA: f64 = 0.05;
pub const R_SCALE_MIN: f64 = 1.0;
pub const R_SCALE_MAX: f64 = 9.0;
pub const XCHECK_TAU_S: f64 = 60.0;
pub const XCHECK_MIN_S: f64 = 120.0;
pub const XCHECK_ENTER_ABS_MPS: f64 = 0.4;
pub const XCHECK_ENTER_REL: f64 = 0.15;
pub const XCHECK_EXIT_ABS_MPS: f64 = 0.2;
pub const XCHECK_EXIT_REL: f64 = 0.08;
pub const XCHECK_PERSIST_S: f64 = 60.0;
pub const XCHECK_MAX_SPAN_S: f64 = 5.0;
pub const DEBIAS_FULL_MPS: f64 = 0.5;
pub const DEBIAS_ZERO_MPS: f64 = 1.0;
pub const ZUPT_NO_STEP_S: f64 = 6.0;
pub const ZUPT_VEL_SIGMA_MPS: f64 = 0.1;
pub const ZUPT_DOPPLER_OVERRIDE_MPS: f64 = 1.0;
pub const ZUPT_RELEASE_M: f64 = 40.0;
pub const SPEC_VERSION: &str = "1.2";
pub const DEFAULT_MAX_SPEED_MPS: f64 = 10.0;

const DEG_TO_RAD: f64 = core::f64::consts::PI / 180.0;

/// 1-D constant-velocity Kalman filter: state `[p, v]`, covariance
/// `[[a, b], [b, c]]`.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Axis {
    p: f64,
    v: f64,
    a: f64,
    b: f64,
    c: f64,
}

impl Axis {
    const fn new(p: f64, pos_var: f64) -> Self {
        Self {
            p,
            v: 0.0,
            a: pos_var,
            b: 0.0,
            c: INIT_VEL_VAR,
        }
    }

    fn predict(&mut self, dt: f64) {
        self.p += self.v * dt;
        let a = self.a + 2.0 * dt * self.b + dt * dt * self.c + Q_ACCEL * libm::pow(dt, 3.0) / 3.0;
        let b = self.b + dt * self.c + Q_ACCEL * dt * dt / 2.0;
        let c = self.c + Q_ACCEL * dt;
        self.a = a;
        self.b = b;
        self.c = c;
    }

    fn update_pos(&mut self, z: f64, r: f64) {
        let s = self.a + r;
        let k0 = self.a / s;
        let k1 = self.b / s;
        let y = z - self.p;
        self.p += k0 * y;
        self.v += k1 * y;
        let (a, b, c) = (self.a, self.b, self.c);
        self.a = (1.0 - k0) * a;
        self.b = (1.0 - k0) * b;
        self.c = c - k1 * b;
    }

    fn update_vel(&mut self, z: f64, r: f64) {
        let s = self.c + r;
        let k0 = self.b / s;
        let k1 = self.c / s;
        let y = z - self.v;
        self.p += k0 * y;
        self.v += k1 * y;
        let (a, b, c) = (self.a, self.b, self.c);
        self.a = a - k0 * b;
        self.b = (1.0 - k1) * b;
        self.c = (1.0 - k1) * c;
    }

    /// Gate lock-out re-anchor: position jumps to `z`, velocity is kept.
    fn reset_pos(&mut self, z: f64, r: f64) {
        self.p = z;
        self.a = r;
        self.b = 0.0;
    }
}

/// Wraps a longitude difference (inputs within [-180, 180]) into [-180, 180).
fn wrap_lng(d: f64) -> f64 {
    if d >= 180.0 {
        d - 360.0
    } else if d < -180.0 {
        d + 360.0
    } else {
        d
    }
}

/// Usable, debiased Doppler speed and its sigma, or `None`.
fn doppler_speed(
    speed_mps: Option<f64>,
    speed_accuracy_mps: Option<f64>,
    max_speed_mps: f64,
) -> Option<(f64, f64)> {
    let speed = valid(speed_mps).filter(|s| (0.0..=max_speed_mps).contains(s))?;
    let reported = valid(speed_accuracy_mps).filter(|s| *s > 0.0);
    let sa = reported.unwrap_or(DEFAULT_SPEED_SIGMA_MPS);
    if sa > MAX_SPEED_SIGMA_MPS {
        return None;
    }
    let mut s = speed;
    if reported.is_some() && s < DEBIAS_ZERO_MPS {
        let w = if s <= DEBIAS_FULL_MPS {
            1.0
        } else {
            (DEBIAS_ZERO_MPS - s) / (DEBIAS_ZERO_MPS - DEBIAS_FULL_MPS)
        };
        s = libm::sqrt((s * s - w * sa * sa).max(0.0));
    }
    Some((s, sa))
}

fn valid(x: Option<f64>) -> Option<f64> {
    x.filter(|v| v.is_finite())
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GpsDistanceEstimator {
    max_speed_mps: f64,
    expected_interval_s: f64,
    gap_s: f64,
    fresh_fix_s: f64,
    gps_distance_m: f64,
    step_distance_m: f64,
    stride_m: Option<f64>,
    origin: Option<(f64, f64)>,
    axes: Option<(Axis, Axis)>,
    t: Option<f64>,
    win_steps: i64,
    win_m: f64,
    last_steps: Option<i64>,
    last_step_t: Option<f64>,
    pending_step_m: f64,
    r_scale: f64,
    rejected_fixes: u32,
    reject_streak: u32,
    zupt_fixes: u32,
    doppler_trusted: bool,
    steps_seen: bool,
    zupt_released: bool,
    xc_doppler: f64,
    xc_pos: f64,
    xc_time: f64,
    xc_persist_s: f64,
    /// `(x, y, t)` of the last fix whose position the filter took.
    xc_last: (f64, f64, f64),
    last_step_inc_t: f64,
    zupt_anchor: Option<(f64, f64)>,
}

/// One estimator lives in the `Recorder`, which the firmware holds once, so
/// the pin is about noticing growth rather than a hard ceiling. Measured at
/// spec v1.2: v1.1's 248 B plus 112 B for the gate, adaptive-R, cross-check
/// and ZUPT state. The state stays `f64`: the projection and the covariance
/// recursion over a run of thousands of fixes do not hold the vectors' 1e-3 m
/// in `f32`. Identical on both targets because every field is 8-aligned
/// scalars, `u32`s and `bool`s.
const _: () = assert!(core::mem::size_of::<GpsDistanceEstimator>() == 360);

impl Default for GpsDistanceEstimator {
    fn default() -> Self {
        Self::new(DEFAULT_MAX_SPEED_MPS)
    }
}

impl GpsDistanceEstimator {
    pub const fn new(max_speed_mps: f64) -> Self {
        Self::with_config(max_speed_mps, 1.0, None)
    }

    /// `expected_interval_s` is the interval the receiver is sampled at on
    /// purpose: it scales the gap and fresh-fix windows, so a 60 s mode is not
    /// re-anchored on every fix. `initial_stride_m` carries a stride learned
    /// earlier and is ignored outside [`MIN_STRIDE_M`]..=[`MAX_STRIDE_M`].
    pub const fn with_config(
        max_speed_mps: f64,
        expected_interval_s: f64,
        initial_stride_m: Option<f64>,
    ) -> Self {
        let scale = if expected_interval_s.is_finite() && expected_interval_s > 1.0 {
            expected_interval_s
        } else {
            1.0
        };
        let stride_m = match initial_stride_m {
            Some(s) if s.is_finite() && s >= MIN_STRIDE_M && s <= MAX_STRIDE_M => Some(s),
            _ => None,
        };
        Self {
            max_speed_mps,
            expected_interval_s,
            gap_s: GAP_S * scale,
            fresh_fix_s: FRESH_FIX_S * scale,
            gps_distance_m: 0.0,
            step_distance_m: 0.0,
            stride_m,
            origin: None,
            axes: None,
            t: None,
            win_steps: 0,
            win_m: 0.0,
            last_steps: None,
            last_step_t: None,
            pending_step_m: 0.0,
            r_scale: 1.0,
            rejected_fixes: 0,
            reject_streak: 0,
            zupt_fixes: 0,
            doppler_trusted: true,
            steps_seen: false,
            zupt_released: false,
            xc_doppler: 0.0,
            xc_pos: 0.0,
            xc_time: 0.0,
            xc_persist_s: 0.0,
            xc_last: (0.0, 0.0, 0.0),
            last_step_inc_t: 0.0,
            zupt_anchor: None,
        }
    }

    pub fn distance_m(&self) -> f64 {
        self.gps_distance_m + self.step_distance_m
    }

    pub fn gps_distance_m(&self) -> f64 {
        self.gps_distance_m
    }

    pub fn step_distance_m(&self) -> f64 {
        self.step_distance_m
    }

    pub fn stride_m(&self) -> Option<f64> {
        self.stride_m
    }

    pub fn r_scale(&self) -> f64 {
        self.r_scale
    }

    pub fn rejected_fixes(&self) -> u32 {
        self.rejected_fixes
    }

    pub fn zupt_fixes(&self) -> u32 {
        self.zupt_fixes
    }

    pub fn doppler_trusted(&self) -> bool {
        self.doppler_trusted
    }

    /// The pedometer says stationary: steps seen this run, none for
    /// [`ZUPT_NO_STEP_S`], and trusted Doppler not contradicting it.
    fn zupt_due(&self, t: f64, dop: Option<f64>) -> bool {
        if !self.steps_seen || self.zupt_released || t - self.last_step_inc_t <= ZUPT_NO_STEP_S {
            return false;
        }
        !matches!(dop, Some(d) if self.doppler_trusted && d >= ZUPT_DOPPLER_OVERRIDE_MPS)
    }

    /// A fresh estimator for the segment after a pause: same configuration,
    /// seeded with this one's stride, which is itself the carried stride when
    /// this segment learned none.
    pub const fn next_segment(&self) -> Self {
        Self::with_config(self.max_speed_mps, self.expected_interval_s, self.stride_m)
    }

    pub fn max_speed_mps(&self) -> f64 {
        self.max_speed_mps
    }

    pub fn expected_interval_s(&self) -> f64 {
        self.expected_interval_s
    }

    /// Clock of the last fix the filter took, `None` before the first.
    pub fn last_fix_t(&self) -> Option<f64> {
        self.t
    }

    /// `t` is seconds on a clock monotonic within the run. Returns the metres
    /// this fix credited.
    #[allow(clippy::too_many_arguments)]
    pub fn add_fix(
        &mut self,
        t: f64,
        lat: f64,
        lng: f64,
        accuracy_m: Option<f64>,
        speed_mps: Option<f64>,
        speed_accuracy_mps: Option<f64>,
        bearing_deg: Option<f64>,
    ) -> f64 {
        if !(t.is_finite() && lat.is_finite() && lng.is_finite()) {
            return 0.0;
        }
        let (lat0, lng0) = *self.origin.get_or_insert((lat, lng));
        let zx = wrap_lng(lng - lng0) * DEG_TO_RAD * EARTH_RADIUS_M * libm::cos(lat0 * DEG_TO_RAD);
        let zy = (lat - lat0) * DEG_TO_RAD * EARTH_RADIUS_M;
        let sigma = valid(accuracy_m)
            .filter(|a| *a > 0.0)
            .unwrap_or(MIN_POS_SIGMA_M);
        let floored = sigma.max(MIN_POS_SIGMA_M);
        let r_stated = floored * floored;
        let r = (r_stated * self.r_scale).max(MIN_POS_SIGMA_M * MIN_POS_SIGMA_M);

        if let Some(last) = self.t {
            if t <= last {
                return 0.0;
            }
        }
        let doppler = doppler_speed(speed_mps, speed_accuracy_mps, self.max_speed_mps);
        let dop = doppler.map(|(s, _)| s);
        let (mut x, mut y, last) = match (self.axes, self.t) {
            (Some((x, y)), Some(last)) if t - last <= self.gap_s => (x, y, last),
            _ => {
                // (Re-)anchor. Steps buffered across a real gap are committed now.
                if self.t.is_some() {
                    self.step_distance_m += self.pending_step_m;
                }
                self.pending_step_m = 0.0;
                self.axes = Some((Axis::new(zx, r), Axis::new(zy, r)));
                self.t = Some(t);
                self.xc_last = (zx, zy, t);
                self.reject_streak = 0;
                self.zupt_anchor = None;
                return 0.0;
            }
        };
        // The gap closed inside the gap window, so the filter integrates it: drop the buffer.
        self.pending_step_m = 0.0;
        let dt = t - last;
        self.t = Some(t);
        x.predict(dt);
        y.predict(dt);

        // 1. Innovation gate on the predicted position.
        let (yx, yy) = (zx - x.p, zy - y.p);
        let (pax, pay) = (x.a, y.a);
        let nis = yx * yx / (pax + r) + yy * yy / (pay + r);
        let accepted = nis <= GATE_CHI2;
        if accepted {
            self.reject_streak = 0;
            x.update_pos(zx, r);
            y.update_pos(zy, r);
            // 2. Adaptive R: covariance matching, sample clamped, EMA, bounded.
            let sample =
                (((yx * yx - pax) + (yy * yy - pay)) / (2.0 * r_stated)).clamp(0.0, R_SCALE_MAX);
            let ema = (1.0 - R_SCALE_ALPHA) * self.r_scale + R_SCALE_ALPHA * sample;
            self.r_scale = ema.clamp(R_SCALE_MIN, R_SCALE_MAX);
        } else {
            self.rejected_fixes += 1;
            self.reject_streak += 1;
            if self.reject_streak > GATE_MAX_REJECTS {
                x.reset_pos(zx, r);
                y.reset_pos(zy, r);
                self.reject_streak = 0;
                self.xc_last = (zx, zy, t);
            }
        }

        // 3. Pedometer zero-velocity update.
        let mut zupt = self.zupt_due(t, dop);
        let mut chord = None;
        if zupt {
            match self.zupt_anchor {
                None => self.zupt_anchor = Some((x.p, y.p)),
                Some((ax, ay)) => {
                    let moved = libm::hypot(x.p - ax, y.p - ay);
                    if moved > ZUPT_RELEASE_M {
                        // The pedometer stalled while the runner moved: stop trusting it until it counts again.
                        self.zupt_released = true;
                        self.zupt_anchor = None;
                        zupt = false;
                        chord = Some(moved);
                    }
                }
            }
        } else {
            self.zupt_anchor = None;
        }
        if zupt {
            self.zupt_fixes += 1;
            let rz = ZUPT_VEL_SIGMA_MPS * ZUPT_VEL_SIGMA_MPS;
            x.update_vel(0.0, rz);
            y.update_vel(0.0, rz);
        }

        // 4. Doppler-vs-position cross-check: Doppler speed against the raw
        //    fixes' displacement projected on the Doppler bearing.
        let bearing = valid(bearing_deg);
        if accepted {
            let (lx, ly, lt) = self.xc_last;
            let span = t - lt;
            if let (Some(d), Some(bd), false) = (dop, bearing, zupt) {
                if d >= POS_ONLY_STATIONARY_SPEED_MPS && span <= XCHECK_MAX_SPAN_S {
                    let b = bd * DEG_TO_RAD;
                    let u = ((zx - lx) * libm::sin(b) + (zy - ly) * libm::cos(b)) / span;
                    if self.xc_time == 0.0 {
                        self.xc_doppler = d;
                        self.xc_pos = d;
                    } else {
                        let alpha = (span / XCHECK_TAU_S).min(1.0);
                        self.xc_doppler += alpha * (d - self.xc_doppler);
                        self.xc_pos += alpha * (u - self.xc_pos);
                    }
                    self.xc_time += span;
                    if self.xc_time >= XCHECK_MIN_S {
                        let diff = (self.xc_doppler - self.xc_pos).abs();
                        let reference = self.xc_pos.abs();
                        let flip = if self.doppler_trusted {
                            diff > XCHECK_ENTER_ABS_MPS.max(XCHECK_ENTER_REL * reference)
                        } else {
                            diff < XCHECK_EXIT_ABS_MPS.max(XCHECK_EXIT_REL * reference)
                        };
                        self.xc_persist_s = if flip { self.xc_persist_s + span } else { 0.0 };
                        if self.xc_persist_s >= XCHECK_PERSIST_S {
                            self.doppler_trusted = !self.doppler_trusted;
                            self.xc_persist_s = 0.0;
                        }
                    }
                }
            }
            self.xc_last = (zx, zy, t);
        }

        // 5. Doppler velocity update.
        let use_dop = doppler.filter(|_| self.doppler_trusted);
        if let (Some((d, sa)), Some(bd), false) = (use_dop, bearing, zupt) {
            if d >= STATIONARY_SPEED_MPS {
                let sa_floored = sa.max(MIN_SPEED_SIGMA_MPS);
                let rv = sa_floored * sa_floored;
                let b = bd * DEG_TO_RAD;
                x.update_vel(d * libm::sin(b), rv);
                y.update_vel(d * libm::cos(b), rv);
            }
        }
        self.axes = Some((x, y));

        // 6. Credit.
        let inc = match (chord, zupt) {
            (Some(c), _) => c,
            (None, true) => 0.0,
            (None, false) => {
                let (speed, floor) = match use_dop {
                    Some((d, _)) => (d, STATIONARY_SPEED_MPS),
                    None => (libm::hypot(x.v, y.v), POS_ONLY_STATIONARY_SPEED_MPS),
                };
                if speed < floor {
                    0.0
                } else {
                    speed.min(self.max_speed_mps) * dt
                }
            }
        };
        self.gps_distance_m += inc;
        self.win_m += inc;
        inc
    }

    /// Cumulative pedometer count. Learns a stride while GPS is good and
    /// buffers steps x stride while it is not; the buffer is committed only
    /// when the gap turns out to exceed [`GAP_S`] x the expected interval.
    pub fn add_steps(&mut self, t: f64, cumulative_steps: i64) {
        if !t.is_finite() {
            return;
        }
        let (prev, prev_t) = (self.last_steps, self.last_step_t);
        self.last_steps = Some(cumulative_steps);
        self.last_step_t = Some(t);
        let (Some(prev), Some(prev_t)) = (prev, prev_t) else {
            return;
        };
        if cumulative_steps < prev || t <= prev_t {
            return;
        }
        let d = cumulative_steps - prev;
        if d > 0 {
            self.steps_seen = true;
            self.last_step_inc_t = t;
            self.zupt_released = false;
        }
        if let Some(fix_t) = self.t {
            if t - fix_t <= self.fresh_fix_s {
                self.win_steps += d;
                if self.win_steps >= STRIDE_WINDOW_STEPS {
                    let stride = self.win_m / self.win_steps as f64;
                    if (MIN_STRIDE_M..=MAX_STRIDE_M).contains(&stride) {
                        self.stride_m = Some(match self.stride_m {
                            None => stride,
                            Some(s) => (1.0 - STRIDE_EMA_ALPHA) * s + STRIDE_EMA_ALPHA * stride,
                        });
                    }
                    self.win_steps = 0;
                    self.win_m = 0.0;
                }
                return;
            }
        }
        self.win_steps = 0;
        self.win_m = 0.0;
        let Some(stride) = self.stride_m else {
            return;
        };
        self.pending_step_m += (d as f64 * stride).min(self.max_speed_mps * (t - prev_t));
    }

    /// End of run: commit buffered steps if the trailing gap exceeds [`GAP_S`]
    /// x the expected interval.
    pub fn finish(&mut self, t: f64) {
        if let Some(fix_t) = self.t {
            if t.is_finite() && t - fix_t > self.gap_s {
                self.step_distance_m += self.pending_step_m;
            }
        }
        self.pending_step_m = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const VECTORS: &str = include_str!("../../../../fixtures/gps_distance_vectors.json");

    fn opt(v: &serde_json::Value, key: &str) -> Option<f64> {
        v.get(key).and_then(serde_json::Value::as_f64)
    }

    #[test]
    fn the_golden_vectors_replay_within_tolerance() {
        let doc: serde_json::Value = serde_json::from_str(VECTORS).expect("vectors parse");
        let tol = doc["tolerance_m"].as_f64().expect("tolerance_m");
        let scenarios = doc["scenarios"].as_array().expect("scenarios");
        assert!(!scenarios.is_empty());
        for sc in scenarios {
            let name = sc["name"].as_str().unwrap_or("?");
            let mut e = GpsDistanceEstimator::with_config(
                sc["maxSpeedMps"].as_f64().expect("maxSpeedMps"),
                sc["expectedIntervalS"].as_f64().expect("expectedIntervalS"),
                sc["initialStrideM"].as_f64(),
            );
            let events = sc["events"].as_array().expect("events");
            let want = sc["expected"]["distanceAfterEachEventM"]
                .as_array()
                .expect("expected");
            assert_eq!(
                events.len(),
                want.len(),
                "{name}: one expectation per event"
            );
            for (i, ev) in events.iter().enumerate() {
                let t = ev["t"].as_f64().expect("t");
                match ev["type"].as_str() {
                    Some("fix") => {
                        e.add_fix(
                            t,
                            opt(ev, "lat").unwrap_or(f64::NAN),
                            opt(ev, "lng").unwrap_or(f64::NAN),
                            opt(ev, "acc"),
                            opt(ev, "speed"),
                            opt(ev, "speedAcc"),
                            opt(ev, "bearing"),
                        );
                    }
                    Some("steps") => {
                        if let Some(count) = ev["count"].as_i64() {
                            e.add_steps(t, count);
                        }
                    }
                    Some("finish") => e.finish(t),
                    other => panic!("{name}: unknown event {other:?}"),
                }
                let expected = want[i].as_f64().expect("number");
                assert!(
                    (e.distance_m() - expected).abs() <= tol,
                    "{name}: after event {i} got {} want {expected}",
                    e.distance_m()
                );
            }
            let exp = &sc["expected"];
            let gps = exp["gpsDistanceM"].as_f64().expect("gpsDistanceM");
            let step = exp["stepDistanceM"].as_f64().expect("stepDistanceM");
            assert!((e.gps_distance_m() - gps).abs() <= tol, "{name}: gps");
            assert!((e.step_distance_m() - step).abs() <= tol, "{name}: step");
            match exp["strideM"].as_f64() {
                Some(s) => assert!(
                    (e.stride_m().expect("stride learned") - s).abs() <= tol,
                    "{name}: stride"
                ),
                None => assert!(e.stride_m().is_none(), "{name}: no stride"),
            }
            assert_eq!(
                Some(u64::from(e.rejected_fixes())),
                exp["rejectedFixes"].as_u64(),
                "{name}: rejectedFixes"
            );
            assert_eq!(
                Some(u64::from(e.zupt_fixes())),
                exp["zuptFixes"].as_u64(),
                "{name}: zuptFixes"
            );
            let r_scale = exp["rScale"].as_f64().expect("rScale");
            assert!((e.r_scale() - r_scale).abs() <= 1e-6, "{name}: rScale");
            assert_eq!(
                Some(e.doppler_trusted()),
                exp["dopplerTrusted"].as_bool(),
                "{name}: dopplerTrusted"
            );
        }
    }

    #[test]
    fn the_fixture_constants_are_this_port_s_constants() {
        let doc: serde_json::Value = serde_json::from_str(VECTORS).expect("vectors parse");
        let c = &doc["constants"];
        let f = |k: &str| c[k].as_f64().unwrap_or_else(|| panic!("constant {k}"));
        assert_eq!(f("EARTH_RADIUS_M"), EARTH_RADIUS_M);
        assert_eq!(f("Q_ACCEL"), Q_ACCEL);
        assert_eq!(f("MIN_POS_SIGMA_M"), MIN_POS_SIGMA_M);
        assert_eq!(f("INIT_VEL_VAR"), INIT_VEL_VAR);
        assert_eq!(f("MIN_SPEED_SIGMA_MPS"), MIN_SPEED_SIGMA_MPS);
        assert_eq!(f("DEFAULT_SPEED_SIGMA_MPS"), DEFAULT_SPEED_SIGMA_MPS);
        assert_eq!(f("MAX_SPEED_SIGMA_MPS"), MAX_SPEED_SIGMA_MPS);
        assert_eq!(f("STATIONARY_SPEED_MPS"), STATIONARY_SPEED_MPS);
        assert_eq!(
            f("POS_ONLY_STATIONARY_SPEED_MPS"),
            POS_ONLY_STATIONARY_SPEED_MPS
        );
        assert_eq!(f("GAP_S"), GAP_S);
        assert_eq!(f("FRESH_FIX_S"), FRESH_FIX_S);
        assert_eq!(f("STRIDE_WINDOW_STEPS") as i64, STRIDE_WINDOW_STEPS);
        assert_eq!(f("MIN_STRIDE_M"), MIN_STRIDE_M);
        assert_eq!(f("MAX_STRIDE_M"), MAX_STRIDE_M);
        assert_eq!(f("STRIDE_EMA_ALPHA"), STRIDE_EMA_ALPHA);
        assert_eq!(f("GATE_CHI2"), GATE_CHI2);
        assert_eq!(f("GATE_MAX_REJECTS") as u32, GATE_MAX_REJECTS);
        assert_eq!(f("R_SCALE_ALPHA"), R_SCALE_ALPHA);
        assert_eq!(f("R_SCALE_MIN"), R_SCALE_MIN);
        assert_eq!(f("R_SCALE_MAX"), R_SCALE_MAX);
        assert_eq!(f("XCHECK_TAU_S"), XCHECK_TAU_S);
        assert_eq!(f("XCHECK_MIN_S"), XCHECK_MIN_S);
        assert_eq!(f("XCHECK_ENTER_ABS_MPS"), XCHECK_ENTER_ABS_MPS);
        assert_eq!(f("XCHECK_ENTER_REL"), XCHECK_ENTER_REL);
        assert_eq!(f("XCHECK_EXIT_ABS_MPS"), XCHECK_EXIT_ABS_MPS);
        assert_eq!(f("XCHECK_EXIT_REL"), XCHECK_EXIT_REL);
        assert_eq!(f("XCHECK_PERSIST_S"), XCHECK_PERSIST_S);
        assert_eq!(f("XCHECK_MAX_SPAN_S"), XCHECK_MAX_SPAN_S);
        assert_eq!(f("DEBIAS_FULL_MPS"), DEBIAS_FULL_MPS);
        assert_eq!(f("DEBIAS_ZERO_MPS"), DEBIAS_ZERO_MPS);
        assert_eq!(f("ZUPT_NO_STEP_S"), ZUPT_NO_STEP_S);
        assert_eq!(f("ZUPT_VEL_SIGMA_MPS"), ZUPT_VEL_SIGMA_MPS);
        assert_eq!(f("ZUPT_DOPPLER_OVERRIDE_MPS"), ZUPT_DOPPLER_OVERRIDE_MPS);
        assert_eq!(f("ZUPT_RELEASE_M"), ZUPT_RELEASE_M);
    }

    #[test]
    fn the_fixture_is_this_port_s_spec_version() {
        let doc: serde_json::Value = serde_json::from_str(VECTORS).expect("vectors parse");
        assert_eq!(SPEC_VERSION, "1.2");
        assert_eq!(doc["spec"].as_str(), Some("gps-distance-estimator v1.2"));
    }

    #[test]
    fn a_doppler_fix_credits_speed_times_interval() {
        let mut e = GpsDistanceEstimator::default();
        assert_eq!(
            e.add_fix(0.0, 40.0, -75.0, Some(4.0), Some(3.0), None, None),
            0.0
        );
        let inc = e.add_fix(2.0, 40.00005, -75.0, Some(4.0), Some(3.0), None, None);
        assert!((inc - 6.0).abs() < 1e-12);
    }

    #[test]
    fn a_gap_over_ten_seconds_reanchors_without_credit() {
        let mut e = GpsDistanceEstimator::default();
        e.add_fix(0.0, 40.0, -75.0, None, Some(3.0), None, None);
        assert_eq!(
            e.add_fix(30.0, 40.001, -75.0, None, Some(3.0), None, None),
            0.0
        );
        assert_eq!(e.distance_m(), 0.0);
    }

    fn learn_stride(e: &mut GpsDistanceEstimator) {
        let deg_per_m = 180.0 / (core::f64::consts::PI * EARTH_RADIUS_M);
        e.add_fix(0.0, 45.0, 7.0, Some(5.0), Some(0.0), Some(0.5), Some(0.0));
        e.add_steps(0.5, 0);
        for i in 1..=20i64 {
            let t = i as f64;
            let lat = 45.0 + 3.0 * t * deg_per_m;
            e.add_fix(t, lat, 7.0, Some(5.0), Some(3.0), Some(0.5), Some(0.0));
            e.add_steps(t + 0.5, 3 * i);
        }
    }

    #[test]
    fn the_next_segment_carries_the_learned_stride_and_the_configuration() {
        let mut first = GpsDistanceEstimator::with_config(6.0, 15.0, None);
        learn_stride(&mut first);
        assert!((first.stride_m().expect("learned") - 1.0).abs() < 1e-9);
        let next = first.next_segment();
        assert!((next.stride_m().expect("carried") - 1.0).abs() < 1e-9);
        assert_eq!(next.max_speed_mps(), 6.0);
        assert_eq!(next.expected_interval_s(), 15.0);
        assert_eq!(next.distance_m(), 0.0);
        assert_eq!(next.last_fix_t(), None);
    }

    #[test]
    fn a_segment_that_learned_nothing_passes_on_its_seed() {
        let seeded = GpsDistanceEstimator::with_config(DEFAULT_MAX_SPEED_MPS, 1.0, Some(0.95));
        assert_eq!(seeded.next_segment().next_segment().stride_m(), Some(0.95));
        assert_eq!(
            GpsDistanceEstimator::default().next_segment().stride_m(),
            None
        );
        let out_of_range = GpsDistanceEstimator::with_config(DEFAULT_MAX_SPEED_MPS, 1.0, Some(3.0));
        assert_eq!(out_of_range.stride_m(), None);
    }

    #[test]
    fn a_carried_stride_blends_with_the_next_learned_one() {
        let mut e = GpsDistanceEstimator::with_config(DEFAULT_MAX_SPEED_MPS, 1.0, Some(0.95));
        learn_stride(&mut e);
        assert!((e.stride_m().expect("blended") - 0.96).abs() < 1e-9);
    }

    #[test]
    fn a_minute_interval_is_not_a_gap_when_it_is_the_expected_one() {
        let mut e = GpsDistanceEstimator::with_config(DEFAULT_MAX_SPEED_MPS, 60.0, None);
        e.add_fix(0.0, 40.0, -75.0, None, Some(3.0), None, None);
        let inc = e.add_fix(60.0, 40.0016, -75.0, None, Some(3.0), None, None);
        assert!((inc - 180.0).abs() < 1e-9);
        assert_eq!(
            e.add_fix(661.0, 40.02, -75.0, None, Some(3.0), None, None),
            0.0
        );
    }

    #[test]
    fn the_estimator_fits_a_static_without_an_allocator() {
        static E: GpsDistanceEstimator = GpsDistanceEstimator::new(DEFAULT_MAX_SPEED_MPS);
        assert_eq!(E.distance_m(), 0.0);
    }
}
