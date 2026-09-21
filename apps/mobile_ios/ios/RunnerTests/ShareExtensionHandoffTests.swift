import XCTest

/// The Share Extension and the host app never call each other: the extension
/// writes JSON into an App Group's `UserDefaults` and opens a URL, and
/// `receive_sharing_intent` reads it back on the other side. Nothing in the
/// compiler joins the two, so every literal that has to agree is compared
/// here instead.
///
/// `SharedRouteHandoff.swift` has target membership in both ShareExtension
/// and RunnerTests, which is what lets this bundle see the constants at all.
/// The plists are read off disk relative to `#filePath` rather than out of
/// `Bundle.main`, because the entitlements files never appear in a bundle —
/// they are compiled into a code signature this simulator build does not
/// have.
final class ShareExtensionHandoffTests: XCTestCase {

    /// `<repo>/apps/mobile_ios/ios`.
    private static let iosRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func plist(_ relativePath: String) throws -> [String: Any] {
        let url = Self.iosRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )
        return try XCTUnwrap(parsed as? [String: Any], "\(relativePath) is not a dictionary")
    }

    private func appGroups(inEntitlements relativePath: String) throws -> [String] {
        let value = try plist(relativePath)["com.apple.security.application-groups"]
        return try XCTUnwrap(
            value as? [String],
            "\(relativePath) declares no com.apple.security.application-groups array"
        )
    }

    // MARK: - The App Group, spelled in four places

    func testHostAppEntitlementsDeclareTheSharedAppGroup() throws {
        let groups = try appGroups(inEntitlements: "Runner/Runner.entitlements")
        XCTAssertTrue(
            groups.contains(SharedRouteHandoff.appGroup),
            "Runner.entitlements must declare \(SharedRouteHandoff.appGroup); it declares \(groups)"
        )
    }

    func testShareExtensionEntitlementsDeclareTheSameAppGroup() throws {
        let groups = try appGroups(inEntitlements: "ShareExtension/ShareExtension.entitlements")
        XCTAssertEqual(groups, [SharedRouteHandoff.appGroup])
    }

    func testHostAppInfoPlistNamesTheGroupTheExtensionWritesTo() throws {
        // `AppGroupId` is `kAppGroupIdKey` in receive_sharing_intent. Absent or
        // wrong, the plugin looks in `group.<bundle id>` — a suite nothing
        // writes — and every share yields an empty read with no error.
        let declared = try plist("Runner/Info.plist")["AppGroupId"] as? String
        XCTAssertEqual(declared, SharedRouteHandoff.appGroup)
    }

    func testHostAppRegistersTheRedirectScheme() throws {
        let hostId = try XCTUnwrap(
            SharedRouteHandoff.hostBundleIdentifier(
                fromExtensionBundleIdentifier: "com.threkir.app.ShareExtension"
            )
        )
        let urlTypes = try XCTUnwrap(plist("Runner/Info.plist")["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(
            schemes.contains("\(SharedRouteHandoff.schemePrefix)-\(hostId)"),
            "Info.plist CFBundleURLTypes must register the redirect scheme; it has \(schemes)"
        )
    }

    // MARK: - The activation rule vs. the "Open with" declaration

    func testTheShareSheetAcceptsExactlyTheTypesOpenWithDeclares() throws {
        // Two entry points, one parser. A type the share sheet accepts but
        // `CFBundleDocumentTypes` does not (or the reverse) is a file the
        // user can hand over one way and not the other, for no reason they
        // can see.
        let documentTypes = try XCTUnwrap(
            plist("Runner/Info.plist")["CFBundleDocumentTypes"] as? [[String: Any]]
        )
        let declared = Set(documentTypes.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })

        let extensionSection = try XCTUnwrap(
            plist("ShareExtension/Info.plist")["NSExtension"] as? [String: Any]
        )
        let attributes = try XCTUnwrap(
            extensionSection["NSExtensionAttributes"] as? [String: Any]
        )
        let rule = try XCTUnwrap(attributes["NSExtensionActivationRule"] as? String)

        for type in declared {
            XCTAssertTrue(
                rule.contains("\"\(type)\""),
                "the share extension's activation rule does not accept \(type), which \"Open with\" does"
            )
        }
        // The reverse direction: no UTI in the rule that is not declared.
        for match in rule.split(separator: "\"").enumerated() where match.offset % 2 == 1 {
            XCTAssertTrue(
                declared.contains(String(match.element)),
                "the activation rule accepts \(match.element), which CFBundleDocumentTypes does not declare"
            )
        }
    }

    // MARK: - The wire format

    func testPayloadEncodesTheShapeThePluginDecodes() throws {
        // receive_sharing_intent's host side decodes this into
        // `SharedMediaFile: Codable` — `path` and `type` required, `type` a
        // `SharedMediaType` whose raw values are image/video/text/file/url.
        // An unknown key is ignored; a missing or misspelled one throws away
        // the whole payload, silently, because the decode is a `try?`.
        let payload = try SharedRouteHandoff.encodedPayload(for: [
            SharedRouteHandoff.MediaFile(
                path: "file:///tmp/Canal loop.gpx",
                mimeType: "application/gpx+xml",
                type: SharedRouteHandoff.MediaFile.fileType
            ),
        ])
        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: payload) as? [[String: Any]]
        )
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0]["path"] as? String, "file:///tmp/Canal loop.gpx")
        XCTAssertEqual(decoded[0]["mimeType"] as? String, "application/gpx+xml")
        XCTAssertEqual(decoded[0]["type"] as? String, "file")
    }

    func testTheSharedPathIsAFileURLNotABarePath() throws {
        // The plugin resolves anything that is not `file://`-prefixed (or
        // under /var/mobile/Media, /private/var/mobile) as a Photos local
        // identifier, finds nothing, and drops the entry. A bare container
        // path therefore imports nothing and reports nothing.
        let container = URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/ABC")
        let destination = container.appendingPathComponent("Canal loop.gpx")
        let path = try XCTUnwrap(destination.absoluteString.removingPercentEncoding)
        XCTAssertTrue(path.hasPrefix("file://"))
        XCTAssertFalse(path.contains("%20"))
    }

    // MARK: - The redirect URL

    func testHostBundleIdentifierDropsTheExtensionSuffix() {
        XCTAssertEqual(
            SharedRouteHandoff.hostBundleIdentifier(
                fromExtensionBundleIdentifier: "com.threkir.app.ShareExtension"
            ),
            "com.threkir.app"
        )
        XCTAssertNil(SharedRouteHandoff.hostBundleIdentifier(fromExtensionBundleIdentifier: "threkir"))
        XCTAssertNil(SharedRouteHandoff.hostBundleIdentifier(fromExtensionBundleIdentifier: ".leading"))
    }

    func testRedirectURLCarriesThePrefixThePluginMatchesOn() throws {
        let url = try XCTUnwrap(
            SharedRouteHandoff.redirectURL(hostBundleIdentifier: "com.threkir.app")
        )
        XCTAssertEqual(url.absoluteString, "ShareMedia-com.threkir.app:share")
    }
}
