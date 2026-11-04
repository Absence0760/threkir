import 'package:flutter/foundation.dart';

/// Time since the app started, on a clock that never steps.
///
/// For ordering a read against something that happened on this device (a
/// delete landing, a conversation opened). `DateTime.now()` follows the wall
/// clock, which NTP can step backwards after the device sleeps, and a marker
/// stamped before the step then outranks every read started after it.
Duration monotonicNow() => debugMonotonicNowOverride?.call() ?? _clock.elapsed;

final Stopwatch _clock = Stopwatch()..start();

/// Replaces [monotonicNow] in a test, so two stamps can be made to tie or to
/// fall in a chosen order; the real clock cannot be made to do either. Reset
/// it to null in `addTearDown`.
@visibleForTesting
Duration Function()? debugMonotonicNowOverride;
