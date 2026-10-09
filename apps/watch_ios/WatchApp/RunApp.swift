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
        // Info.plist expands both keys from build settings that only a
        // release defines (scripts/ios_watch_runtime_config.mjs), so every
        // other build reads them as empty strings: no DSN means no Sentry,
        // and no release means "dev" (decisions § 1819).
        let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String ?? ""
        if !dsn.isEmpty {
            let plistRelease = Bundle.main.object(forInfoDictionaryKey: "APP_RELEASE") as? String ?? ""
            let release = plistRelease.isEmpty ? "dev" : plistRelease
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
