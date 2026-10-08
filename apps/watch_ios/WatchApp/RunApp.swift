import SwiftUI
import HealthKit
import WatchKit
#if canImport(Sentry)
import Sentry
#endif

/// The workout session watchOS kept alive across an app termination, handed
/// from the application delegate to whichever `WorkoutManager` takes it.
enum SurvivingWorkout {
    static let handoff = PendingHandoff<HKWorkoutSession>()
}

/// Receives the one launch watchOS makes on a workout's behalf: an app
/// terminated while its `HKWorkoutSession` was running is relaunched into
/// `handleActiveWorkoutRecovery()`, and the session goes on recording in
/// Health whether or not anything here takes it back. Until this existed the
/// session was orphaned and the run ended at its last checkpoint
/// (decisions § 1793).
final class RunAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        HealthKitManager.recoverActiveWorkoutSession { survivor in
            SurvivingWorkout.handoff.deliver(survivor)
        }
    }
}

@main
struct RunApp: App {
    @WKApplicationDelegateAdaptor(RunAppDelegate.self) private var appDelegate

    init() {
        #if canImport(Sentry)
        // Crash reporting + breadcrumb trail for production builds.
        // Add the `sentry-cocoa` SwiftPM package to the watchOS target
        // and define `SENTRY_DSN` + `APP_RELEASE` in the Xcode build
        // settings (Other Swift Flags: `-DSENTRY_DSN=...`) — or read
        // from Info.plist. Off when DSN is empty (dev / debug).
        let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String ?? ""
        if !dsn.isEmpty {
            let release = (Bundle.main.object(forInfoDictionaryKey: "APP_RELEASE") as? String) ?? "dev"
            SentrySDK.start { options in
                options.dsn = dsn
                options.releaseName = release
                options.environment = release == "dev" ? "development" : "production"
                options.tracesSampleRate = 0.1
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
