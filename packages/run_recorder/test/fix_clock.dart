import 'package:geolocator/geolocator.dart';
import 'package:run_recorder/run_recorder.dart';

/// A monotonic clock for [RunRecorder]'s `clock:` that advances to each fix's
/// GPS time, the way real time passes on a phone between fixes. Tests inject
/// fixes back to back, so the real [Stopwatch] would read microseconds for a
/// 12 s dropout and the estimator would time the gap by machine speed
/// (#1356). Like a real stopwatch it only advances while running: a fix
/// injected while stopped is ignored, and the first fix after a restart reads
/// as arriving the moment the clock restarted, so a pause stays out of it.
///
/// A GPS clock that goes backwards or stalls leaves it where it was, so it
/// cannot drive the tests where the monotonic clock must advance while GPS
/// time does not (decisions § 348); those advance a clock by hand.
class FixClock extends Stopwatch {
  Duration _value = Duration.zero;
  DateTime? _lastFix;

  @override
  Duration get elapsed => _value;

  @override
  void stop() {
    super.stop();
    _lastFix = null;
  }

  @override
  void reset() {
    super.reset();
    _value = Duration.zero;
    _lastFix = null;
  }

  void advanceTo(DateTime gpsTime) {
    if (!isRunning) return;
    final last = _lastFix;
    if (last != null && !gpsTime.isAfter(last)) return;
    if (last != null) _value += gpsTime.difference(last);
    _lastFix = gpsTime;
  }

  void inject(RunRecorder r, Position pos) {
    advanceTo(pos.timestamp);
    r.debugInjectPosition(pos);
  }
}
