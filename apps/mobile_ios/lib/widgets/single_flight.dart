/// One "await, then open" at a time.
///
/// A handler that reads something (a run from the network, gear for a
/// picker) before it pushes a screen or opens a sheet leaves a window the
/// length of that read, and a second tap in it opened a second copy: two run
/// details stacked so Back showed the same run again, two gear pickers whose
/// second Save overwrote the first (issue #1374 NS-11). Route the handler
/// through [openOnce] and a tap while one is still resolving is dropped.
///
/// Hold one per screen (a field on its `State`), or one per surface that
/// should open a single thing at a time. `single_flight_guard_test.dart`
/// fails an async body that awaits anything but a route or dialog and then
/// opens one, unless it runs inside [openOnce].
class SingleFlight {
  bool _busy = false;

  /// Whether an [openOnce] is still resolving.
  bool get busy => _busy;

  /// Runs [open] unless another is in flight, in which case this call does
  /// nothing. [open] holds the slot until it completes, including while a
  /// route it awaits is open, so returning from that route frees it.
  Future<void> openOnce(Future<void> Function() open) async {
    if (_busy) return;
    _busy = true;
    try {
      await open();
    } finally {
      _busy = false;
    }
  }
}
