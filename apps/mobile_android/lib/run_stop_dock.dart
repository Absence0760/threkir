import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Whether the shell's docked centre button is the recorder's Stop control.
///
/// On the phone shell the centre button sits directly under the recorder's
/// control row, and a second red Stop a thumb's width above it was two
/// controls for one act. So while a run records on the Run page the docked
/// button IS the Stop, and the recorder panel leaves its own out. The
/// NavigationRail layout docks nothing, so it publishes `false` and the panel
/// keeps its Stop: absent from the tree also means `false`, so a recorder
/// mounted anywhere else can always be stopped.
class RunStopDock extends InheritedWidget {
  const RunStopDock({super.key, required this.docked, required super.child});

  final bool docked;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RunStopDock>()?.docked ??
      false;

  @override
  bool updateShouldNotify(RunStopDock oldWidget) => oldWidget.docked != docked;
}

/// A completed hold on the docked Stop, delivered to the recorder.
///
/// The shell owns the button and `RunScreen` owns the run, so the hold is a
/// request the recorder acts on rather than a callback the shell reaches
/// into the recorder for. A recorder that isn't recording ignores it.
class RunStopRequests extends ChangeNotifier {
  void request() => notifyListeners();
}

final RunStopRequests runStopRequests = RunStopRequests();
