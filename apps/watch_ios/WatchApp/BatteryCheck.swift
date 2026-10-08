import Foundation
import WatchKit

/// The pre-run battery warning: the single most common way a long run is
/// lost is starting it on a watch that was already half drained, and nothing
/// on the start screen said so.
///
/// The watchOS half of Wear OS's `BatteryStatus`
/// (`apps/watch_wear/.../system/BatteryStatus.kt`), same threshold and same
/// rule: the warning advises and never blocks the start, and a level the
/// platform will not report is "unknown", which warns of nothing.
enum BatteryCheck {
    /// Below this the start screen suggests charging. Wear's
    /// `LOW_THRESHOLD_PERCENT`, held to the same figure so the two wrists
    /// give the same advice on the same battery.
    static let lowThresholdPercent = 40

    /// `WKInterfaceDevice.batteryLevel` as a whole percent, or nil when the
    /// platform has nothing to say — it reports -1 with monitoring off and on
    /// a simulator.
    static func percent(fromLevel level: Float) -> Int? {
        guard level.isFinite, level >= 0, level <= 1 else { return nil }
        return Int((level * 100).rounded())
    }

    /// The percent to warn about, or nil when there is nothing to warn of.
    static func warningPercent(fromLevel level: Float) -> Int? {
        guard let percent = percent(fromLevel: level), percent < lowThresholdPercent else { return nil }
        return percent
    }

    /// Read once, when the start screen appears. Monitoring is switched on
    /// for the read and left on: it costs nothing the workout does not
    /// already cost, and switching it off would race a second read.
    static func currentWarningPercent() -> Int? {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        return warningPercent(fromLevel: device.batteryLevel)
    }
}
