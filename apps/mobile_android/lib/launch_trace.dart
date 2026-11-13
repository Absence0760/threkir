/// How long each cold-start phase took, and how much it loaded, kept until
/// error reporting can carry it.
///
/// An iOS watchdog termination arrives in Sentry with no stack (THREKIR-
/// CLIENT-B): the OS ended the process for a main-thread stall or for memory,
/// and the event says only that. The launch is where this app does its
/// heaviest synchronous work — every local store is read and decoded before
/// the first frame — and it all runs before Sentry is initialised, because
/// the opt-out lives in one of those stores. So `main` times the phases here
/// and hands them to Sentry as breadcrumbs once (and only if) it is running:
/// the next watchdog event then carries how long the launch took and how many
/// runs and track points it left in memory.
///
/// Counts and durations only; no ids, names or coordinates.
class LaunchTrace {
  LaunchTrace({Stopwatch? clock}) : _clock = clock ?? (Stopwatch()..start());

  final Stopwatch _clock;
  final List<LaunchMark> _marks = [];
  bool _flushed = false;

  List<LaunchMark> get marks => List.unmodifiable(_marks);

  /// Records [phase] at the current offset from the start of the launch.
  void mark(String phase, [Map<String, Object> data = const {}]) {
    _marks.add(LaunchMark(phase, _clock.elapsedMilliseconds, data));
  }

  /// Runs [body] and records how long it took as [phase], also when it
  /// throws. A trace must never change what the launch does.
  Future<T> time<T>(String phase, Future<T> Function() body) async {
    final started = _clock.elapsedMilliseconds;
    try {
      return await body();
    } finally {
      _marks.add(LaunchMark(phase, _clock.elapsedMilliseconds, {
        'took_ms': _clock.elapsedMilliseconds - started,
      }));
    }
  }

  /// Hands every mark to [sink] once. Later calls do nothing, so a second
  /// flush cannot double the breadcrumbs.
  void flush(void Function(LaunchMark mark) sink) {
    if (_flushed) return;
    _flushed = true;
    for (final m in _marks) {
      sink(m);
    }
  }
}

class LaunchMark {
  const LaunchMark(this.phase, this.atMs, this.data);

  final String phase;

  /// Milliseconds since `main` started.
  final int atMs;

  final Map<String, Object> data;

  Map<String, Object> get breadcrumbData => {'at_ms': atMs, ...data};
}
