/// Time since the app started, on a clock that never steps.
///
/// For ordering a read against something that happened on this device (a
/// delete landing, a conversation opened). `DateTime.now()` follows the wall
/// clock, which NTP can step backwards after the device sleeps, and a marker
/// stamped before the step then outranks every read started after it.
Duration monotonicNow() => _clock.elapsed;

final Stopwatch _clock = Stopwatch()..start();
