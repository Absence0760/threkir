import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';

/// A recording whose run screen was torn down while it was still live,
/// checkpointed at the moment of tear-down, waiting for the next run screen
/// to offer Resume / Finish / Discard on it.
///
/// The recorder lives in the run screen's State, so anything that unmounts
/// that State mid-run ends the GPS session with it. The shell is built so
/// that a layout change cannot (decisions § 2352), but a State dispose is the
/// last line, not the first: whatever caused it, the run is handed on here and
/// written to the in-progress file rather than dropped. Cleared at sign-out
/// with the in-progress file it mirrors ([wipeInProgressRecording]).
final ValueNotifier<Run?> orphanedRecording = ValueNotifier<Run?>(null);
