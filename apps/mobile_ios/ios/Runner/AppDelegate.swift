import AudioToolbox
import CoreMotion
import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // No `FirebaseApp.configure()` here, and the Firebase console's "Add
  // initialisation code" step is what asks for one. Adding it would be
  // redundant rather than helpful: `+[FLTFirebaseCorePlugin sharedInstance]`
  // already calls `+[FIRApp configureWithOptions:]` whenever a
  // GoogleService-Info.plist is bundled, and GeneratedPluginRegistrant below
  // is what reaches it.
  //
  // Which means the configure runs during plugin registration, BEFORE any
  // Dart does, so `initFirebaseForPush()`'s try/catch sits downstream of it
  // and cannot catch it — it only ever guarded the Dart-side call. An ABSENT
  // plist is still safe (`FIROptions.defaultOptions` is nil, nothing is
  // configured, and the Dart side disables push off `Firebase.apps.isEmpty`).
  // A MALFORMED one raises an uncaught NSException here and the process takes
  // SIGABRT at launch, which no Dart code can degrade. That is why the
  // Runner's "Copy Firebase config if present" build phase validates the file
  // rather than leaving it to the app.
  //
  // The console's SDK step is equally inapplicable: the Firebase pods
  // arrive through the FlutterFire plugins' generated Podfile, so adding Swift
  // Package Manager packages by hand would resolve the SDK a second time.
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register the background-sync launch handler before launch completes.
    // BGTaskScheduler only delivers a task whose handler was registered
    // during didFinishLaunching, and this app adopts UIScene — Flutter
    // registers plugins during scene connection, after this returns — so the
    // plugin cannot do it for us and the call has to be here.
    //
    // Must be the BGProcessingTask registrar, not the periodic one: the Dart
    // side submits a BGProcessingTaskRequest (see `registerBackgroundSync`),
    // and the handler dispatches on the delivered task's type. Registering
    // the wrong type leaves the request unhandled. Identifier must match
    // `backgroundSyncTaskName` in Dart and the lone entry in Info.plist's
    // BGTaskSchedulerPermittedIdentifiers.
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "com.threkir.backgroundSync"
    )

    // Keep the on-device GPS/HR run cache out of iCloud / iTunes backups.
    // The Flutter app writes every local run, route, gym and food JSON
    // file under Documents (path_provider's getApplicationDocumentsDirectory
    // → NSDocumentDirectory); all of it is sensitive-but-re-derivable — the
    // durable copy lives server-side and re-syncs. Excluding the directory
    // node excludes its whole subtree from backup. OS Data Protection still
    // encrypts these files at rest; this only closes the cloud-backup-
    // extraction path. See decisions.md (at-rest / backup posture).
    excludeDocumentsFromBackup()

    // Start listening for Apple Watch file transfers before the Flutter
    // engine spins up. Runs that arrive while the engine is still
    // loading are buffered in-process and flushed to Dart once the
    // method channel is attached below.
    WatchIngestBridge.shared.activate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Best-effort (L4): a failure here must never block launch. Idempotent —
  // setting the flag every cold start is cheap and the directory always
  // exists for an installed app.
  private func excludeDocumentsFromBackup() {
    let fm = FileManager.default
    guard var docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    do {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try docs.setResourceValues(values)
    } catch {
      NSLog("Failed to exclude Documents from iCloud backup: \(error)")
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Before the generated plugins: scene URL delivery stops at the first
    // delegate that reports a URL handled, and receive_sharing_intent claims
    // every cold-launch URL — including the document opens it ignores.
    engineBridge.pluginRegistry.registrar(forPlugin: "DocumentOpenHandoff")?
      .addSceneDelegate(DocumentOpenHandoff.shared)
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // `FlutterPluginRegistry` conforms to `FlutterBinaryMessenger`, so
    // the registry doubles as the messenger for our custom channel.
    if let messenger = engineBridge.pluginRegistry as? FlutterBinaryMessenger {
      WatchIngestBridge.shared.attach(binaryMessenger: messenger)
      CalendarBridge.shared.attach(binaryMessenger: messenger)
      LiveActivityBridge.shared.attach(binaryMessenger: messenger)
      ScreenBrightnessBridge.shared.attach(binaryMessenger: messenger)
      BarometerBridge.shared.attach(binaryMessenger: messenger)
      RunHapticsBridge.shared.attach(binaryMessenger: messenger)
    }
  }
}

/// Full brightness while the parkrun barcode is on screen. iOS has no
/// per-window override, so this saves the runner's level before raising it and
/// puts it back on `restore`, which the Dart side also sends whenever the app
/// leaves the foreground. Dart side: `lib/screen_brightness_bridge.dart` over
/// `run_app/screen_brightness`. Kept in this file so it needs no new entry in
/// the Xcode project.
final class ScreenBrightnessBridge {
  static let shared = ScreenBrightnessBridge()

  private var channel: FlutterMethodChannel?
  private var saved: CGFloat?

  func attach(binaryMessenger: FlutterBinaryMessenger) {
    let brightness = FlutterMethodChannel(
      name: "run_app/screen_brightness",
      binaryMessenger: binaryMessenger
    )
    brightness.setMethodCallHandler { call, result in
      switch call.method {
      case "setMax":
        if self.saved == nil { self.saved = UIScreen.main.brightness }
        UIScreen.main.brightness = 1.0
        result(nil)
      case "restore":
        if let level = self.saved { UIScreen.main.brightness = level }
        self.saved = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = brightness
  }
}

/// Run cues on the vibration motor, over `run_app/haptics`. Dart side:
/// `lib/run_haptics_bridge.dart`, which names the pattern; Android's table is
/// `RunHapticPatterns.kt`.
///
/// The system vibrate sound, not Core Haptics or UIFeedbackGenerator: those
/// only play while the app is in the foreground, and a run is recorded with
/// the phone locked in a pocket. A background-location app may still play the
/// vibrate sound. It has one fixed length, so a pattern here is a pulse count,
/// each pulse chained off the previous one's completion. Kept in this file so
/// it needs no new entry in the Xcode project.
final class RunHapticsBridge {
  static let shared = RunHapticsBridge()

  static let pulses: [String: Int] = [
    "step_work": 3,
    "step_ease": 2,
    "workout_complete": 4,
    "pace_speed_up": 2,
    "pace_slow_down": 1,
  ]

  private var channel: FlutterMethodChannel?

  func attach(binaryMessenger: FlutterBinaryMessenger) {
    let haptics = FlutterMethodChannel(
      name: "run_app/haptics",
      binaryMessenger: binaryMessenger
    )
    haptics.setMethodCallHandler { call, result in
      guard call.method == "play" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let name = call.arguments as? String,
        let count = RunHapticsBridge.pulses[name]
      else {
        result(
          FlutterError(
            code: "bad_args", message: "unknown haptic pattern", details: nil))
        return
      }
      RunHapticsBridge.vibrate(times: count)
      result(true)
    }
    channel = haptics
  }

  private static func vibrate(times: Int) {
    guard times > 0 else { return }
    AudioServicesPlaySystemSoundWithCompletion(kSystemSoundID_Vibrate) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        RunHapticsBridge.vibrate(times: times - 1)
      }
    }
  }
}

/// The barometer's relative altitude for the run recorder's elevation, over
/// `run_app/barometer`. Dart side: `lib/barometer_bridge.dart`. CMAltimeter
/// starts every session at 0 m, so only the shape is used; the recorder levels
/// it against GPS altitude (`BaroAltitudeAnchor`). Rides the Motion & Fitness
/// permission the pedometer already asks for. Kept in this file so it needs no
/// new entry in the Xcode project.
final class BarometerBridge: NSObject, FlutterStreamHandler {
  static let shared = BarometerBridge()

  private let altimeter = CMAltimeter()
  private var channel: FlutterEventChannel?

  func attach(binaryMessenger: FlutterBinaryMessenger) {
    let events = FlutterEventChannel(
      name: "run_app/barometer",
      binaryMessenger: binaryMessenger
    )
    events.setStreamHandler(self)
    channel = events
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    altimeter.stopRelativeAltitudeUpdates()
    guard CMAltimeter.isRelativeAltitudeAvailable() else {
      return FlutterError(code: "unavailable", message: "no barometer", details: nil)
    }
    switch CMAltimeter.authorizationStatus() {
    case .denied, .restricted:
      return FlutterError(code: "permission", message: "motion access denied", details: nil)
    default:
      break
    }
    altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { data, error in
      if let error = error {
        events(FlutterError(code: "unavailable", message: error.localizedDescription, details: nil))
        return
      }
      guard let data = data else { return }
      events(["altitudeM": data.relativeAltitude.doubleValue])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    altimeter.stopRelativeAltitudeUpdates()
    return nil
  }
}
