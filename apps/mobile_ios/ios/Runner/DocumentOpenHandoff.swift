import Flutter
import UIKit
import UniformTypeIdentifiers
import receive_sharing_intent

/// iOS document "Open with" for a route file: the counterpart of Android's
/// `ACTION_VIEW` intent-filter, and the half `CFBundleDocumentTypes` only
/// declares.
///
/// The OS delivers the document as a plain `file://` URL, and
/// `receive_sharing_intent` answers only its own `ShareMedia-<bundle id>`
/// scheme, so without this the open reached no Dart at all. Rather than a
/// second channel, the file is put through the Share Extension's handoff —
/// staged under the App Group's `SharedRoutes/`, described in the same
/// `UserDefaults` payload, and announced to the plugin with the same
/// redirect URL — so `lib/shared_file_import.dart` receives it exactly as it
/// receives a share.
///
/// Registered as a scene life-cycle delegate AHEAD of the generated plugins
/// (`AppDelegate.didInitializeImplicitFlutterEngine`): Flutter stops at the
/// first delegate that reports a URL handled, and `receive_sharing_intent`
/// reports every cold-launch URL handled whether it acted on it or not.
final class DocumentOpenHandoff: NSObject, FlutterSceneLifeCycleDelegate {
    static let shared = DocumentOpenHandoff()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions?
    ) -> Bool {
        guard let connectionOptions else { return false }
        let consumed = deliver(connectionOptions.urlContexts, coldLaunch: true)
        return consumed && connectionOptions.userActivities.isEmpty
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
        deliver(URLContexts, coldLaunch: false)
    }

    /// True when every URL was a document this delivered, so the remaining
    /// delegates are left any URL that is not.
    private func deliver(_ contexts: Set<UIOpenURLContext>, coldLaunch: Bool) -> Bool {
        let documents = contexts.filter { Self.isDocumentOpen($0.url) }
        guard !documents.isEmpty else { return false }

        let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedRouteHandoff.appGroup)
            .flatMap { SharedRouteHandoff.preparedPayloadDirectory(in: $0) }
        let files = documents.map {
            Self.stage($0.url, openInPlace: $0.options.openInPlace, into: directory)
        }

        guard let defaults = UserDefaults(suiteName: SharedRouteHandoff.appGroup),
              let payload = try? SharedRouteHandoff.encodedPayload(for: files),
              let hostId = Bundle.main.bundleIdentifier,
              let redirect = SharedRouteHandoff.redirectURL(hostBundleIdentifier: hostId)
        else {
            NSLog("DocumentOpenHandoff: could not hand \(files.count) document(s) to Dart")
            return false
        }
        defaults.set(payload, forKey: SharedRouteHandoff.userDefaultsKey)

        // The plugin's own entry points, not a self-opened URL: a cold launch
        // has to land in `initialMedia` (what `getInitialMedia` returns once
        // Dart is up), and only the launch path sets it. A warm open goes to
        // the event stream Dart is already listening on.
        let plugin = ReceiveSharingIntentPlugin.instance
        if coldLaunch {
            _ = plugin.application(
                UIApplication.shared,
                didFinishLaunchingWithOptions: [UIApplication.LaunchOptionsKey.url: redirect]
            )
        } else {
            _ = plugin.application(UIApplication.shared, open: redirect, options: [:])
        }
        return documents.count == contexts.count
    }

    static func isDocumentOpen(_ url: URL) -> Bool {
        url.isFileURL
    }

    /// Moves or copies `source` into `directory` and describes the result.
    ///
    /// `LSSupportsOpeningDocumentsInPlace` is false, so iOS normally hands over
    /// a copy in `Documents/Inbox` that the app owns: that is MOVED, or every
    /// route ever opened would sit in Inbox forever. An in-place open is the
    /// sender's file, so it is only copied, under its security scope. When
    /// staging fails, or there is no App Group to stage into, the entry names
    /// the source itself — readable for an Inbox copy, and for anything else
    /// a read failure Dart reports as "couldn't import" rather than silence.
    static func stage(
        _ source: URL,
        openInPlace: Bool,
        into directory: URL?,
        fileManager: FileManager = .default
    ) -> SharedRouteHandoff.MediaFile {
        var delivered = source
        if let directory {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                if openInPlace {
                    try fileManager.copyItem(at: source, to: destination)
                } else {
                    try fileManager.moveItem(at: source, to: destination)
                }
                delivered = destination
            } catch {
                NSLog("DocumentOpenHandoff: staging \(source.lastPathComponent) failed: \(error)")
            }
        }
        return SharedRouteHandoff.MediaFile(
            path: SharedRouteHandoff.payloadPath(for: delivered),
            mimeType: UTType(filenameExtension: delivered.pathExtension)?.preferredMIMEType,
            type: SharedRouteHandoff.MediaFile.fileType
        )
    }
}
