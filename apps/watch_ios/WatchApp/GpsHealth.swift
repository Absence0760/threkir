import Foundation

/// Why the recorder decided to restart `CLLocationManager` updates.
enum GpsRetryTrigger: Equatable {
    /// Updates are not running, so nothing can arrive until they are.
    case notRunning
    /// Updates are running and CoreLocation has gone quiet for longer than
    /// [GpsHealth.stallSeconds].
    case stalled
}

/// The self-heal decision the watch makes about its own GPS stream, pure.
///
/// Pure because neither failure mode can be produced on a simulator: it
/// serves whatever location Xcode is configured to serve and never wedges, so
/// the only honest coverage of a dropout is a decision function driven over
/// synthetic clocks.
///
/// The clock it reads is DELIVERY, not accepted fixes: a stream handing over
/// only 100 m fixes proves the subsystem is alive, and restarting CoreLocation
/// cannot clear a tree canopy — a kick that cannot help is a retry hiding a
/// non-bug.
enum GpsHealth {
    /// Poll interval for the self-heal check. Matches Wear OS's
    /// `GPS_RETRY_INTERVAL_MS`.
    static let retryIntervalSeconds: TimeInterval = 10

    /// Silence that makes a live subscription degenerate. Matches Wear OS's
    /// `GPS_STALL_MS`: long enough to ignore the normal 1-3 s gap between
    /// fixes, short enough that the runner has pace back inside half a minute.
    static let stallSeconds: TimeInterval = 30

    /// Whether to restart location updates, and why.
    ///
    /// `lastDeliveryUptime` / `lastRetryUptime` / `nowUptime` are
    /// `ProcessInfo.systemUptime` readings, not wall-clock dates: an NTP step
    /// backwards makes a wall-clock age negative, and a negative age never
    /// exceeds a threshold — freezing the self-heal exactly when a long run
    /// has had time to drift.
    ///
    /// - Parameters:
    ///   - authorized: whether location authorization currently permits fixes.
    ///     Unauthorized returns nil: restarting delivers nothing, and the grant
    ///     arriving later is a delegate callback, not something to poll for.
    ///   - updatesRunning: whether `startUpdatingLocation()` is in effect.
    ///   - lastDeliveryUptime: the last `didUpdateLocations` of any kind, or
    ///     nil when none has arrived this run. Nil is NOT a stall — it is a
    ///     cold acquire or an indoor run, and treating it as one would restart
    ///     CoreLocation every 30 s for the length of a treadmill session.
    ///   - lastRetryUptime: when updates were last (re)started, or nil. Guards
    ///     against thrashing a fresh subscription that also takes a few seconds
    ///     to emit — Wear OS spends its own `lastPointAtMs` on this, which
    ///     leaves the delivery clock saying something other than when a fix
    ///     last arrived.
    static func retryTrigger(
        authorized: Bool,
        updatesRunning: Bool,
        lastDeliveryUptime: TimeInterval?,
        lastRetryUptime: TimeInterval?,
        nowUptime: TimeInterval
    ) -> GpsRetryTrigger? {
        guard authorized else { return nil }
        guard updatesRunning else { return .notRunning }
        guard let lastDelivery = lastDeliveryUptime else { return nil }
        guard nowUptime - lastDelivery > stallSeconds else { return nil }
        if let lastRetry = lastRetryUptime, nowUptime - lastRetry < stallSeconds { return nil }
        return .stalled
    }
}
