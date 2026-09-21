import ActivityKit
import Flutter
import Foundation

/// Drives the lock-screen / Dynamic Island Live Activity for an in-progress
/// run. Dart side: `lib/live_activity_bridge.dart` over
/// `run_app/live_activity`; the rendering half is the `RunActivityExtension`
/// widget extension, which shares `RunActivityAttributes` with this target.
///
/// This is an L4 auxiliary effect (docs/features/run_recording.md §
/// Layering). ActivityKit is absent below iOS 16.2, off whenever the runner
/// has turned Live Activities off for the app, and refuses a request once the
/// system's activity ceiling is reached — none of those is an error, and none
/// of them may reach the recorder. So every method here answers the channel
/// with a Bool and never with a FlutterError: the Dart client treats a false
/// as "there is no activity", stops offering frames, and the run carries on
/// untouched.
@objc class LiveActivityBridge: NSObject {
    @objc static let shared = LiveActivityBridge()

    /// The activity this process started. Typed `Any?` because the property
    /// cannot carry an `@available` annotation of its own, and the class has
    /// to exist on iOS 15 for `AppDelegate` to attach it.
    private var current: Any?

    @objc func attach(binaryMessenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "run_app/live_activity",
            binaryMessenger: binaryMessenger
        )
        // Strong capture: `shared` is a permanent singleton, so there is no
        // cycle to break — and a weak self going nil would leave the Dart
        // future unanswered forever instead of failing.
        channel.setMethodCallHandler { call, result in
            let args = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "start": result(self.start(args))
            case "update": result(self.update(args))
            case "stop":
                self.stop()
                result(true)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    private func start(_ args: [String: Any]) -> Bool {
        guard #available(iOS 16.2, *) else { return false }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        guard let state = RunActivityAttributes.ContentState(arguments: args) else { return false }
        // A run the process died during leaves its activity on the lock
        // screen until the system's 8-hour staleness expiry. Ending whatever
        // this app already owns before requesting a new one means the worst
        // case is one stranded card until the next run, not one per crash.
        endAll()
        do {
            current = try Activity.request(
                attributes: RunActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil)
            )
            return true
        } catch {
            NSLog("LiveActivityBridge.start failed: \(error.localizedDescription)")
            current = nil
            return false
        }
    }

    private func update(_ args: [String: Any]) -> Bool {
        guard #available(iOS 16.2, *) else { return false }
        guard let activity = current as? Activity<RunActivityAttributes>,
              let state = RunActivityAttributes.ContentState(arguments: args)
        else { return false }
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        return true
    }

    private func stop() {
        guard #available(iOS 16.2, *) else { return }
        current = nil
        endAll()
    }

    /// `.immediate` rather than the default: the run is over, and a card that
    /// lingers on the lock screen showing a dead clock is what the runner
    /// would have to dismiss by hand.
    @available(iOS 16.2, *)
    private func endAll() {
        for activity in Activity<RunActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
