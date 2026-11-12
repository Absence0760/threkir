import XCTest

@testable import Runner

/// `UIOpenURLContext` and `UIScene.ConnectionOptions` cannot be constructed
/// in a test, so what is pinned is everything around them: which URLs count
/// as a document open, how the file is staged into the App Group, and the
/// payload entry Dart is handed for it.
final class DocumentOpenHandoffTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentOpenHandoffTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, in directoryName: String, contents: String = "<gpx/>") throws -> URL {
        let directory = root.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func payloadDirectory() throws -> URL {
        try XCTUnwrap(SharedRouteHandoff.preparedPayloadDirectory(in: root.appendingPathComponent("group")))
    }

    // MARK: - Which URLs are document opens

    func testOnlyFileURLsAreDocumentOpens() throws {
        XCTAssertTrue(DocumentOpenHandoff.isDocumentOpen(URL(fileURLWithPath: "/tmp/Inbox/loop.gpx")))
        // The share extension's redirect and the Supabase auth deep link both
        // belong to other delegates, and must be left for them.
        XCTAssertFalse(DocumentOpenHandoff.isDocumentOpen(try XCTUnwrap(URL(string: "ShareMedia-com.threkir.app:share"))))
        XCTAssertFalse(DocumentOpenHandoff.isDocumentOpen(try XCTUnwrap(URL(string: "com.threkir.app://login-callback?code=x"))))
    }

    // MARK: - Staging

    func testAnInboxCopyIsMovedOutOfInbox() throws {
        let source = try write("Canal loop.gpx", in: "Documents/Inbox")
        let directory = try payloadDirectory()

        let file = DocumentOpenHandoff.stage(source, openInPlace: false, into: directory)

        let staged = directory.appendingPathComponent("Canal loop.gpx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: source.path),
            "an Inbox copy left behind accumulates with every route ever opened"
        )
        XCTAssertEqual(file.path, "file://\(staged.path)")
        XCTAssertEqual(file.type, SharedRouteHandoff.MediaFile.fileType)
    }

    func testAnInPlaceOpenIsCopiedAndTheSendersFileIsLeftAlone() throws {
        let source = try write("loop.kml", in: "Elsewhere", contents: "<kml/>")
        let directory = try payloadDirectory()

        let file = DocumentOpenHandoff.stage(source, openInPlace: true, into: directory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let staged = directory.appendingPathComponent("loop.kml")
        XCTAssertEqual(try String(contentsOf: staged, encoding: .utf8), "<kml/>")
        XCTAssertEqual(file.path, "file://\(staged.path)")
    }

    func testWithNoAppGroupTheEntryNamesTheSourceItself() throws {
        let source = try write("loop.gpx", in: "Documents/Inbox")

        let file = DocumentOpenHandoff.stage(source, openInPlace: false, into: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(file.path, "file://\(source.path)")
    }

    func testAFailedStageFallsBackToTheSource() throws {
        let missing = root.appendingPathComponent("Documents/Inbox/gone.gpx")
        let directory = try payloadDirectory()

        let file = DocumentOpenHandoff.stage(missing, openInPlace: false, into: directory)

        // Dart's read of this path fails and banners "couldn't import", which
        // is the point: an open that went wrong still tells the user.
        XCTAssertEqual(file.path, "file://\(missing.path)")
    }

    func testThePayloadPathIsNotPercentEncoded() throws {
        // Dart's `File()` does not decode, so `%20` would name a file that
        // does not exist.
        let source = try write("Long run 2026.gpx", in: "Documents/Inbox")
        let file = DocumentOpenHandoff.stage(source, openInPlace: false, into: try payloadDirectory())
        XCTAssertFalse(file.path.contains("%20"))
        XCTAssertTrue(file.path.hasPrefix("file://"))
    }

    func testTheMimeTypeComesFromTheDeclaredUTI() throws {
        let source = try write("loop.gpx", in: "Documents/Inbox")
        let file = DocumentOpenHandoff.stage(source, openInPlace: false, into: try payloadDirectory())
        XCTAssertEqual(file.mimeType, "application/gpx+xml")
    }

    // MARK: - The payload directory

    func testPreparingThePayloadDirectoryEmptiesOnlyThatDirectory() throws {
        let container = root.appendingPathComponent("group", isDirectory: true)
        let stale = try write("previous.gpx", in: "group/\(SharedRouteHandoff.payloadDirectoryName)")
        // The container root holds the UserDefaults suite the payload itself
        // is written to; the sweep must never reach it.
        let preferences = try write("group.com.threkir.app.share.plist", in: "group/Library/Preferences")

        let directory = try XCTUnwrap(SharedRouteHandoff.preparedPayloadDirectory(in: container))

        XCTAssertEqual(directory.lastPathComponent, SharedRouteHandoff.payloadDirectoryName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preferences.path))
    }

    // MARK: - The declaration this staging relies on

    func testInfoPlistAsksForACopyRatherThanAnInPlaceOpen() throws {
        // `stage` moves a non-in-place open out of Inbox. That is only safe
        // because the OS hands over a copy the app owns, which is what this
        // key being false asks for.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Runner/Info.plist")
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["LSSupportsOpeningDocumentsInPlace"] as? Bool, false)
    }
}
