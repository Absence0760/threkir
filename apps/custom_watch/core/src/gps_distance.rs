//! GPS distance estimator, spec v1.1 — the `no_std` port of
//! `scripts/gps_distance/reference.py` (docs/features/gps_distance.md).
//!
//! Summing the straight hop between consecutive raw fixes inflates distance
//! at running pace, because a 1 Hz fix moves about as far as its own error and
//! every zig-zag across the true line adds length. This filters position with
//! two constant-velocity Kalman filters on a local tangent plane, credits the
//! receiver's Doppler speed over ground when it is usable, refuses to credit
//! anything below a stationary floor, and re-anchors across a gap rather than
//! inventing the un-sampled ground.
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
}

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
        let zx = (lng - lng0) * DEG_TO_RAD * EARTH_RADIUS_M * libm::cos(lat0 * DEG_TO_RAD);
        let zy = (lat - lat0) * DEG_TO_RAD * EARTH_RADIUS_M;
        let sigma = valid(accuracy_m)
            .filter(|a| *a > 0.0)
            .unwrap_or(MIN_POS_SIGMA_M);
        let floored = sigma.max(MIN_POS_SIGMA_M);
        let r = floored * floored;

        if let Some(last) = self.t {
            if t <= last {
                return 0.0;
            }
        }
        let (mut x, mut y, last) = match (self.axes, self.t) {
            (Some((x, y)), Some(last)) if t - last <= self.gap_s => (x, y, last),
            _ => {
                if self.t.is_some() {
                    self.step_distance_m += self.pending_step_m;
                }
                self.pending_step_m = 0.0;
                self.axes = Some((Axis::new(zx, r), Axis::new(zy, r)));
                self.t = Some(t);
                return 0.0;
            }
        };
        self.pending_step_m = 0.0;
        let dt = t - last;
        self.t = Some(t);
        x.predict(dt);
        y.predict(dt);
        x.update_pos(zx, r);
        y.update_pos(zy, r);

        let mut doppler = None;
        if let Some(speed) = valid(speed_mps) {
            if (0.0..=self.max_speed_mps).contains(&speed) {
                let sa = valid(speed_accuracy_mps)
                    .filter(|s| *s > 0.0)
                    .unwrap_or(DEFAULT_SPEED_SIGMA_MPS);
                if sa <= MAX_SPEED_SIGMA_MPS {
                    doppler = Some(speed);
                    if let Some(bearing) = valid(bearing_deg) {
                        if speed >= STATIONARY_SPEED_MPS {
                            let sa_floored = sa.max(MIN_SPEED_SIGMA_MPS);
                            let rv = sa_floored * sa_floored;
                            let b = bearing * DEG_TO_RAD;
                            x.update_vel(speed * libm::sin(b), rv);
                            y.update_vel(speed * libm::cos(b), rv);
                        }
                    }
                }
            }
        }
        self.axes = Some((x, y));

        let (speed, floor) = match doppler {
            Some(d) => (d, STATIONARY_SPEED_MPS),
            None => (libm::hypot(x.v, y.v), POS_ONLY_STATIONARY_SPEED_MPS),
        };
        if speed < floor {
            return 0.0;
        }
        let inc = speed.min(self.max_speed_mps) * dt;
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

    #[test]
    fn the_fixture_covers_the_v1_1_scenarios() {
        let doc: serde_json::Value = serde_json::from_str(VECTORS).expect("vectors parse");
        let names: Vec<&str> = doc["scenarios"]
            .as_array()
            .expect("scenarios")
            .iter()
            .filter_map(|s| s["name"].as_str())
            .collect();
        for required in [
            "sparse_15s",
            "sparse_60s_position_only",
            "sparse_without_interval_hint",
            "seeded_stride_gap_fill",
            "seeded_stride_out_of_range",
        ] {
            assert!(
                names.contains(&required),
                "fixture lost scenario {required}"
            );
        }
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
        assert!(core::mem::size_of::<GpsDistanceEstimator>() <= 256);
    }
}
