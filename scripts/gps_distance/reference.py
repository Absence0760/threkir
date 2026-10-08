"""GPS distance estimator — reference implementation, spec v1.

Every port (Dart, TypeScript, Kotlin, Swift, Rust, Go) must reproduce
gps_distance_vectors.json to 1e-3 m. Operation order matters only at the
1e-9 level; keep formulas as written.
"""
import math

EARTH_RADIUS_M = 6371008.8
Q_ACCEL = 0.6                     # m^2/s^3, white-acceleration spectral density
MIN_POS_SIGMA_M = 3.0             # floor on reported horizontal accuracy
INIT_VEL_VAR = 25.0               # (m/s)^2 initial velocity variance
MIN_SPEED_SIGMA_MPS = 0.3         # floor on Doppler speed accuracy
DEFAULT_SPEED_SIGMA_MPS = 0.5     # used when the platform reports none
MAX_SPEED_SIGMA_MPS = 1.5         # Doppler worse than this is ignored
STATIONARY_SPEED_MPS = 0.4        # below: no distance (Doppler present)
POS_ONLY_STATIONARY_SPEED_MPS = 0.8  # below: no distance (no Doppler)
GAP_S = 10.0                      # fix interval above this re-anchors, no credit
FRESH_FIX_S = 2.0                 # a fix this recent counts as "GPS good" for stride learning
STRIDE_WINDOW_STEPS = 50
MIN_STRIDE_M, MAX_STRIDE_M = 0.4, 2.5
STRIDE_EMA_ALPHA = 0.2


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


def _valid(x):
    return x is not None and math.isfinite(x)


class GpsDistanceEstimator:
    def __init__(self, max_speed_mps=10.0):
        self.max_speed_mps = max_speed_mps
        self.gps_distance_m = 0.0
        self.step_distance_m = 0.0
        self.stride_m = None
        self._lat0 = self._lng0 = None
        self._x = self._y = None
        self._t = None
        self._win_steps = 0
        self._win_m = 0.0
        self._last_steps = None
        self._last_step_t = None
        self._pending_step_m = 0.0

    @property
    def distance_m(self):
        return self.gps_distance_m + self.step_distance_m

    def _project(self, lat, lng):
        x = math.radians(lng - self._lng0) * EARTH_RADIUS_M * math.cos(math.radians(self._lat0))
        y = math.radians(lat - self._lat0) * EARTH_RADIUS_M
        return x, y

    def add_fix(self, t, lat, lng, accuracy_m=None, speed_mps=None,
                speed_accuracy_mps=None, bearing_deg=None):
        """t: seconds on a clock monotonic within the run. Returns metres credited."""
        if not (_valid(t) and _valid(lat) and _valid(lng)):
            return 0.0
        if self._lat0 is None:
            self._lat0, self._lng0 = lat, lng
        zx, zy = self._project(lat, lng)
        sigma = accuracy_m if (_valid(accuracy_m) and accuracy_m > 0) else MIN_POS_SIGMA_M
        r = max(sigma, MIN_POS_SIGMA_M) ** 2
        if self._t is not None and t <= self._t:
            return 0.0
        if self._t is None or t - self._t > GAP_S:
            # (Re-)anchor. Steps buffered across a real gap are committed now.
            if self._t is not None:
                self.step_distance_m += self._pending_step_m
            self._pending_step_m = 0.0
            self._x, self._y = _Axis(zx, r), _Axis(zy, r)
            self._t = t
            return 0.0
        # The gap closed inside GAP_S, so the filter integrates it: drop the buffer.
        self._pending_step_m = 0.0
        dt = t - self._t
        self._t = t
        self._x.predict(dt)
        self._y.predict(dt)
        self._x.update_pos(zx, r)
        self._y.update_pos(zy, r)

        doppler = None
        if _valid(speed_mps) and 0.0 <= speed_mps <= self.max_speed_mps:
            sa = speed_accuracy_mps if (_valid(speed_accuracy_mps) and speed_accuracy_mps > 0) \
                else DEFAULT_SPEED_SIGMA_MPS
            if sa <= MAX_SPEED_SIGMA_MPS:
                doppler = speed_mps
                if _valid(bearing_deg) and speed_mps >= STATIONARY_SPEED_MPS:
                    rv = max(sa, MIN_SPEED_SIGMA_MPS) ** 2
                    b = math.radians(bearing_deg)
                    self._x.update_vel(speed_mps * math.sin(b), rv)
                    self._y.update_vel(speed_mps * math.cos(b), rv)

        if doppler is not None:
            speed, floor = doppler, STATIONARY_SPEED_MPS
        else:
            speed, floor = math.hypot(self._x.v, self._y.v), POS_ONLY_STATIONARY_SPEED_MPS
        if speed < floor:
            return 0.0
        inc = min(speed, self.max_speed_mps) * dt
        self.gps_distance_m += inc
        self._win_m += inc
        return inc

    def add_steps(self, t, cumulative_steps):
        """Cumulative pedometer count. Learns stride while GPS is good; buffers
        steps x stride while it is not (committed only if the gap exceeds GAP_S)."""
        if not _valid(t) or cumulative_steps is None:
            return
        prev, prev_t = self._last_steps, self._last_step_t
        self._last_steps, self._last_step_t = cumulative_steps, t
        if prev is None or cumulative_steps < prev or prev_t is None or t <= prev_t:
            return
        d = cumulative_steps - prev
        if self._t is not None and t - self._t <= FRESH_FIX_S:
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
        """End of run: commit buffered steps if the trailing gap exceeds GAP_S."""
        if self._t is not None and _valid(t) and t - self._t > GAP_S:
            self.step_distance_m += self._pending_step_m
        self._pending_step_m = 0.0
