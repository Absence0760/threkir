import Foundation

/// Why the recorder decided to restart `CLLocationManager` updates.
enum GpsRetryTrigger: Equatable {
    /// Updates are not running, so nothing can arrive until they are.
    case notRunning
    /// Updates are running and CoreLocation has gone quiet for longer than
    /// [GpsHealth.stallSeconds].
    case stalled
}

/// What the run screen tells the runner about GPS, in their words.
enum GpsBannerState: Equatable {
    case healthy
    /// No fix has landed yet this run. A treadmill session lives here for its
    /// whole length, which is why it is not phrased as a failure.
    case noFixYet
    /// A fix landed and then the stream went cold.
    case lost
}

/// The two decisions the watch makes about its own GPS stream, both pure.
///
/// Pure because neither can be produced on a simulator: a watchOS simulator
/// serves whatever location Xcode is configured to serve and never wedges, so
/// the only honest coverage of a dropout is a decision function driven over
/// synthetic clocks.
///
/// The two halves deliberately read DIFFERENT clocks. The banner is about the
/// run's data — the last fix that passed the accuracy gate, because a stream
/// delivering only 100 m fixes has frozen the distance exactly as a dead one
/// would, and "GPS lost" is the true thing to say. The retry is about the
/// subsystem — the last delivery of any kind, gated or not, because restarting
/// CoreLocation cannot clear a tree canopy and a kick that cannot help is a
/// retry hiding a non-bug.
enum GpsHealth {
    /// Poll interval for the self-heal check. Matches Wear OS's
    /// `GPS_RETRY_INTERVAL_MS`.
    static let retryIntervalSeconds: TimeInterval = 10

    /// Silence that makes a live subscription degenerate. Matches Wear OS's
    /// `GPS_STALL_MS`: long enough to ignore the normal 1-3 s gap between
    /// fixes, short enough that the runner has pace back inside half a minute.
    static let stallSeconds: TimeInterval = 30

    /// Fix age at which the runner is told the signal is gone. The canonical
    /// mobile recorder's `_gpsLostThreshold` (run_recording.md § Hardening
    /// row 2) — the same product statement, so a runner under the same canopy
    /// is told the same thing on a phone and on a wrist. Deliberately tighter
    /// than [stallSeconds]: telling someone costs nothing, restarting
    /// CoreLocation costs a re-acquire.
    static let lostSeconds: TimeInterval = 10

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
    ///     would corrupt the banner's input here.
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

    /// What to show the runner, from the age of the last ACCEPTED fix.
    ///
    /// One optional rather than a `(hasEverHadFix, age)` pair: the pair can
    /// express "never had a fix, and it was 4 s ago", and a display that can be
    /// handed a contradiction eventually is.
    static func banner(lastAcceptedFixAge: TimeInterval?) -> GpsBannerState {
        guard let age = lastAcceptedFixAge else { return .noFixYet }
        return age > lostSeconds ? .lost : .healthy
    }
}
