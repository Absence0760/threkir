import Flutter
import Foundation
import WidgetKit

/// Stores the Today widget's snapshot where the widget extension can read it,
/// and tells WidgetKit to redraw. Dart writes the snapshot over
/// `run_app/home_widget` (`update` with `snapshot_json`, `clear` on sign-out);
/// the Android twin answers the same channel. The snapshot's shape and the
/// rule for what a day shows live in `RunActivity/TodayWidgetSnapshot.swift`,
/// which this target compiles too.
///
/// An L4 auxiliary effect: the widget is a glance, so nothing here may reach
/// a run. The one failure, an App Group this build is not entitled to,
/// answers with a FlutterError that the Dart caller catches and logs.
final class HomeWidgetBridge {
    static let shared = HomeWidgetBridge()

    private var channel: FlutterMethodChannel?

    func attach(binaryMessenger: FlutterBinaryMessenger) {
        let homeWidget = FlutterMethodChannel(
            name: "run_app/home_widget",
            binaryMessenger: binaryMessenger
        )
        // Strong capture, as in LiveActivityBridge: `shared` is a permanent
        // singleton, so there is no cycle, and a nil self would leave the
        // Dart future unanswered.
        homeWidget.setMethodCallHandler { call, result in
            switch call.method {
            case "update":
                guard let args = call.arguments as? [String: Any],
                      let json = args["snapshot_json"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "snapshot_json missing", details: nil))
                    return
                }
                result(self.answer(self.store(json)))
            case "clear":
                result(self.answer(self.store(nil)))
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        channel = homeWidget
    }

    /// Writes `json` to the widget's App Group, or removes it for nil, and
    /// reloads the widget. False when the group is unavailable, which is the
    /// entitlement missing from this build's signature.
    @discardableResult
    func store(_ json: String?, in defaults: UserDefaults? = TodayWidget.sharedDefaults) -> Bool {
        guard let defaults else { return false }
        if let json {
            defaults.set(json, forKey: TodayWidget.snapshotKey)
        } else {
            defaults.removeObject(forKey: TodayWidget.snapshotKey)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidget.kind)
        return true
    }

    private func answer(_ stored: Bool) -> Any? {
        if stored { return nil }
        return FlutterError(code: "unavailable", message: "widget App Group unavailable", details: nil)
    }
}
