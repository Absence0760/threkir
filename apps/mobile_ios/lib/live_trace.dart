/// The spectator's view of a live run's pings, kept in time order whatever
/// order they arrive in (issue #1300 BUG-003).
///
/// Pings reach the spectator screen from the backlog read, the realtime
/// stream (opened first so nothing lands between the two) and the poll
/// fallback when realtime fails. Appending each arrival drew a ping that
/// arrived late as a spike back to an old position. Every arrival goes
/// through [insertPing] instead.
///
/// Mirrors `apps/web/src/lib/runs/live_trace.ts`
/// (`docs/architecture/parity_pairs.md`).
library;

class TracePing {
  const TracePing({
    required this.lat,
    required this.lng,
    this.distanceM,
    this.elapsedS,
    this.bpm,
    this.ele,
    this.atMs,
    this.coarse = false,
    this.weakGps = false,
  });

  final double lat;
  final double lng;
  final double? distanceM;
  final int? elapsedS;
  final int? bpm;
  final double? ele;

  /// The ping's own clock in epoch ms, or null when it carries none.
  final int? atMs;

  /// The privacy-zone last-seen (migration 20270121_001).
  final bool coarse;

  /// A fix the recorder kept for distance but not for its line (migration
  /// 20271112000030). Drawn as an approximate position, never joined.
  final bool weakGps;
}

enum InsertResult { newest, older, duplicate }

/// An ISO-8601 instant with a time and an explicit offset — what Postgres
/// emits for a `timestamptz`. Anything else (a bare date, a zoneless time, a
/// locale string) is refused rather than resolved in the device's own zone,
/// which `DateTime.tryParse` and JS `Date.parse` do differently.
final RegExp _isoInstant = RegExp(
    r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])[T ]([01]\d|2[0-3]):[0-5]\d(:[0-5]\d(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$');

/// A finite, positive epoch-ms instant for [at], or null. A malformed or
/// non-positive value is no clock at all.
int? pingTimeMs(String? at) {
  if (at == null || !_isoInstant.hasMatch(at)) return null;
  final t = DateTime.tryParse(at);
  if (t == null) return null;
  final ms = t.toUtc().millisecondsSinceEpoch;
  return ms > 0 ? ms : null;
}

bool _samePing(TracePing a, TracePing b) =>
    a.lat == b.lat &&
    a.lng == b.lng &&
    a.distanceM == b.distanceM &&
    a.elapsedS == b.elapsedS;

/// An ordered list of pings. [pings] is kept sorted by time.
class LiveTrace {
  final List<TracePing> _pings = [];
  final List<int> _order = [];

  List<TracePing> get pings => List.unmodifiable(_pings);
  bool get isEmpty => _pings.isEmpty;
  TracePing? get newest => _pings.isEmpty ? null : _pings.last;

  void clear() {
    _pings.clear();
    _order.clear();
  }

  /// Insert [incoming] in time order.
  ///
  /// - A ping with a clock goes where its clock puts it; equal clocks keep
  ///   arrival order.
  /// - A ping without one goes last, at the newest clock seen so far:
  ///   arrival order is the only order it has.
  /// - A ping already present is dropped: same clock and same reading, or,
  ///   for one without a clock, the same reading anywhere in the list.
  InsertResult insertPing(TracePing incoming) {
    final lastOrder = _order.isEmpty ? 0 : _order.last;
    final at = incoming.atMs;
    if (at == null) {
      for (final p in _pings) {
        if (p.atMs == null && _samePing(p, incoming)) {
          return InsertResult.duplicate;
        }
      }
      _pings.add(incoming);
      _order.add(lastOrder);
      return InsertResult.newest;
    }
    var lo = 0;
    var hi = _order.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_order[mid] <= at) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo - 1; i >= 0 && _order[i] == at; i--) {
      if (_pings[i].atMs == at && _samePing(_pings[i], incoming)) {
        return InsertResult.duplicate;
      }
    }
    _pings.insert(lo, incoming);
    _order.insert(lo, at);
    return lo == _pings.length - 1 ? InsertResult.newest : InsertResult.older;
  }

  /// The pings that join the trace line, in time order. Only precise fixes:
  /// a coarse or weak ping is drawn as an approximate marker instead, the
  /// way the saved run keeps those fixes off its line.
  List<TracePing> lineFixes() =>
      [for (final p in _pings) if (!p.coarse && !p.weakGps) p];
}
