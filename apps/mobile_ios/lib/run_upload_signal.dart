import 'package:flutter/foundation.dart';

/// Fires each time one or more runs are known to be on the server, pushed
/// from this device or pulled down from it.
///
/// Linking a run to a planned workout happens in a trigger on `runs`
/// (decisions § 2079), so these are the moments a plan workout's completion
/// can change with no plan write on this device for anything to notice.
/// `TrainingService.followRunsLanded` turns them into a plan refresh.
class RunUploadSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}
