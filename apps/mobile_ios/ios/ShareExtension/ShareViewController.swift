import UIKit
import UniformTypeIdentifiers

/// The iOS system share sheet's entry point into Threkir: the counterpart of
/// the Android manifest's `ACTION_SEND` intent-filter, and the half the
/// existing `CFBundleDocumentTypes` "Open with" registration could never
/// cover — a document type registration only reaches the "Open in" chooser.
///
/// It shows no UI. `NSExtensionActivationRule` in `Info.plist` already limits
/// activation to the two route UTIs the host app declares, so by the time
/// this runs the only question left is whether the file can be materialised;
/// asking the user to confirm a share they just performed would be a second
/// tap for nothing. The outcome — imported, or "couldn't import" — is
/// reported by the host app's own localized banner once it foregrounds
/// (`HomeScreen._onIncomingRouteImport`).
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        importAttachments()
    }

    private func importAttachments() {
        guard let destinationDirectory = preparedPayloadDirectory() else {
            // Either the App Group is not provisioned on this build or the
            // directory could not be made, so there is nowhere to put the
            // file. Handing the host app an unreachable path is deliberate:
            // it routes a broken build into the one failure message the user
            // can act on instead of opening the app onto nothing.
            finish(with: [unreachablePlaceholder()])
            return
        }

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .compactMap { provider -> (NSItemProvider, String)? in
                guard let uti = SharedRouteHandoff.acceptedTypeIdentifiers
                    .first(where: provider.hasItemConformingToTypeIdentifier)
                else { return nil }
                return (provider, uti)
            }

        guard !providers.isEmpty else {
            // Unreachable while the activation rule holds — the OS only
            // offers Threkir for an attachment conforming to one of the two
            // route types. Kept because the rule and this list are two
            // declarations of one set, and the day they disagree the user
            // should be told rather than watch the sheet close on nothing.
            finish(with: [unreachablePlaceholder()])
            return
        }

        let group = DispatchGroup()
        // `loadFileRepresentation` calls back on an arbitrary queue, so the
        // accumulator is guarded rather than assumed single-threaded.
        let lock = NSLock()
        var files: [SharedRouteHandoff.MediaFile] = []

        for (provider, uti) in providers {
            group.enter()
            // `loadFileRepresentation`, not `loadItem`: it materialises a
            // data-backed provider (a file pulled from iCloud, a mail
            // attachment) to a temp file just the same as a file-backed one,
            // so both shapes take one code path. The URL is only valid inside
            // this block, which is why the copy happens here.
            provider.loadFileRepresentation(forTypeIdentifier: uti) { url, error in
                defer { group.leave() }
                let destination = destinationDirectory.appendingPathComponent(
                    Self.fileName(for: url, conformingTo: uti)
                )
                if let url, error == nil {
                    try? FileManager.default.copyItem(at: url, to: destination)
                }
                // The entry is recorded whether or not the copy landed. A
                // path that does not exist fails the host app's single
                // documented failure path (`SharedFileImportService.importPath`
                // catches the read and banners), which is the point: a share
                // the extension could not honour must still tell the user,
                // not close the sheet on nothing.
                lock.lock()
                files.append(
                    SharedRouteHandoff.MediaFile(
                        // A `file://` URL string, NOT `destination.path` — see
                        // `SharedRouteHandoff.encodedPayload`. Percent-encoding
                        // is removed because the plugin hands the string
                        // straight to Dart's `File()`, which does not decode it.
                        path: destination.absoluteString.removingPercentEncoding
                            ?? destination.absoluteString,
                        mimeType: UTType(uti)?.preferredMIMEType,
                        type: SharedRouteHandoff.MediaFile.fileType
                    )
                )
                lock.unlock()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.finish(with: files)
        }
    }

    /// Writes the payload where the host app's plugin reads it, wakes the
    /// host app, and closes the sheet. Never called with an empty list: an
    /// activation that produced no file still hands over a placeholder, so
    /// that the host app has something to fail on and report.
    private func finish(with files: [SharedRouteHandoff.MediaFile]) {
        if let defaults = UserDefaults(suiteName: SharedRouteHandoff.appGroup),
           let payload = try? SharedRouteHandoff.encodedPayload(for: files) {
            defaults.set(payload, forKey: SharedRouteHandoff.userDefaultsKey)
        }
        openHostApp()
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func openHostApp() {
        guard let extensionId = Bundle.main.bundleIdentifier,
              let hostId = SharedRouteHandoff.hostBundleIdentifier(
                  fromExtensionBundleIdentifier: extensionId
              ),
              let url = SharedRouteHandoff.redirectURL(hostBundleIdentifier: hostId)
        else { return }

        // `extensionContext.open(_:)` is documented to work only for a Today
        // extension, so a share extension reaches UIApplication by walking the
        // responder chain — the idiom `receive_sharing_intent`'s own
        // controller uses. iOS 18 stopped answering the `openURL:` selector
        // probe, hence the split.
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                if #available(iOS 18.0, *) {
                    application.open(url, options: [:], completionHandler: nil)
                } else {
                    let selector = sel_registerName("openURL:")
                    if application.responds(to: selector) {
                        _ = application.perform(selector, with: url)
                    }
                }
                return
            }
            responder = current.next
        }
    }

    /// An entry the host app is guaranteed to fail to read — it names the
    /// extension's own temporary directory, which the host app's sandbox
    /// cannot reach even if a file were there. `SharedFileImportService`
    /// turns the failed read into the "couldn't import" banner, which is the
    /// whole point: every activation of this extension ends in a message.
    private func unreachablePlaceholder() -> SharedRouteHandoff.MediaFile {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).gpx")
        return SharedRouteHandoff.MediaFile(
            path: url.absoluteString,
            mimeType: nil,
            type: SharedRouteHandoff.MediaFile.fileType
        )
    }

    /// The directory shared route files are copied into, emptied of whatever
    /// the last share left there and created if it does not exist. Returns nil
    /// when the App Group is not reachable, which is the only case the caller
    /// has to treat as a broken build.
    ///
    /// Emptying it is what stops every file a user ever shared accumulating in
    /// the group container forever — the host app copies what it imports into
    /// its own route store, and nothing else sweeps. It is scoped to this one
    /// directory rather than the container root because the root also holds
    /// the `UserDefaults` suite the payload itself is written to.
    private func preparedPayloadDirectory() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedRouteHandoff.appGroup)
        else { return nil }

        let directory = container.appendingPathComponent(
            SharedRouteHandoff.payloadDirectoryName,
            isDirectory: true
        )
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in contents {
            try? FileManager.default.removeItem(at: file)
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        return directory
    }

    /// The shared file's own name, so the host app's format dispatch still
    /// has an extension to read. A provider can supply neither, in which case
    /// the UTI's preferred extension keeps `detectRouteFormat` on its fast
    /// path instead of leaving it to sniff the content.
    private static func fileName(for url: URL?, conformingTo uti: String) -> String {
        if let name = url?.lastPathComponent, !name.isEmpty, name != "/" { return name }
        let fallbackExtension = UTType(uti)?.preferredFilenameExtension ?? "dat"
        return "\(UUID().uuidString).\(fallbackExtension)"
    }
}
