import Foundation

/// The wire contract between this Share Extension and the host app.
///
/// The host half is NOT ours: `receive_sharing_intent`'s
/// `ReceiveSharingIntentPlugin` already listens for the redirect URL, reads
/// the App Group's `UserDefaults`, and hands the result to
/// `lib/shared_file_import.dart` — the same Dart path the "Open with"
/// (`CFBundleDocumentTypes`) import already uses. So the extension only has
/// to WRITE what that plugin reads.
///
/// Why this file re-declares the shape instead of linking the plugin: the
/// plugin ships its extension-side controller inside a Swift package that
/// depends on `FlutterFramework`. Linking it would drag the Flutter engine
/// into an app extension that never runs Dart, against a share extension's
/// small memory budget, and the package itself only exists under
/// `ios/Flutter/ephemeral/`, which no checkout carries. Three encodable
/// fields and two string keys are the whole contract; `ShareExtensionHandoffTests`
/// pins them.
enum SharedRouteHandoff {
    /// Registered at developer.apple.com → Identifiers → App Groups, and
    /// declared by BOTH `Runner.entitlements` and
    /// `ShareExtension.entitlements`. It is also spelled a third time as
    /// `AppGroupId` in the host app's `Info.plist`, because that is where the
    /// plugin reads it from. A mismatch between any two of those silently
    /// shares nothing — the same trap `ActiveRunBridge.appGroup` carries a
    /// note about — so `ShareExtensionHandoffTests` reads all three off disk
    /// and compares them.
    ///
    /// Deliberately NOT `group.com.threkir.app.activerun`: the extension
    /// wipes this container's root on every activation (see
    /// `ShareViewController`), which would be destructive to a group holding
    /// anything else.
    static let appGroup = "group.com.threkir.app.share"

    /// `kUserDefaultsKey` in the plugin. Value is a JSON array of `MediaFile`.
    static let userDefaultsKey = "ShareKey"

    /// `kSchemePrefix` in the plugin. The host app registers
    /// `ShareMedia-<host bundle id>` in `CFBundleURLTypes`, and the plugin
    /// ignores any URL that does not carry that exact prefix — which is how
    /// two apps built on this plugin avoid waking each other.
    static let schemePrefix = "ShareMedia"

    /// One shared file, in the shape the plugin's host-side
    /// `SharedMediaFile: Codable` decodes. `thumbnail`, `duration` and
    /// `message` are optionals it leaves nil, so they are simply absent here.
    struct MediaFile: Encodable {
        let path: String
        let mimeType: String?
        let type: String

        /// `SharedMediaType.file`'s raw value. The plugin decodes `type` as a
        /// non-optional enum, so an unknown string fails the WHOLE payload.
        static let fileType = "file"
    }

    /// The plugin resolves a shared path by stripping a `file://` prefix and,
    /// failing that, treating the string as a Photos local identifier — so a
    /// bare filesystem path under the App Group container is looked up in
    /// Photos, found to be nothing, and dropped without a word. Every path
    /// written here therefore has to be a `file://` URL string.
    static func encodedPayload(for files: [MediaFile]) throws -> Data {
        try JSONEncoder().encode(files)
    }

    /// The plugin derives the host app's bundle id from the extension's by
    /// dropping the last dot-component, and matches the redirect URL against
    /// it. Replicated here so the two agree by construction rather than by a
    /// literal that would rot on a bundle-id change.
    static func hostBundleIdentifier(fromExtensionBundleIdentifier id: String) -> String? {
        guard let lastDot = id.lastIndex(of: "."), lastDot > id.startIndex else { return nil }
        return String(id[..<lastDot])
    }

    /// `ShareMedia-com.threkir.app:share`.
    static func redirectURL(hostBundleIdentifier: String) -> URL? {
        URL(string: "\(schemePrefix)-\(hostBundleIdentifier):share")
    }
}
