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
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // `FlutterPluginRegistry` conforms to `FlutterBinaryMessenger`, so
    // the registry doubles as the messenger for our custom channel.
    if let messenger = engineBridge.pluginRegistry as? FlutterBinaryMessenger {
      WatchIngestBridge.shared.attach(binaryMessenger: messenger)
      CalendarBridge.shared.attach(binaryMessenger: messenger)
    }
  }
}
