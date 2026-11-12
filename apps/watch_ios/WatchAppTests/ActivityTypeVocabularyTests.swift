import XCTest
@testable import WatchApp

/// Guard-rail: the wrist's `activity_type` vocabulary is the phone's and the
/// web's, in every locale, and covers what the column admits.
///
/// The Apple Watch is the fourth platform to carry this vocabulary. Mobile and
/// web each carried partial copies that fell through to a hand-rolled
/// title-caser, and Wear OS carried abbreviated wrist forms until
/// decisions § 713 and § 1155 resolved both; each of those is now held by an
/// `activity_type_vocabulary` guard of its own
/// (`activity_type_vocabulary_test.dart`, `activity_type_vocabulary.test.ts`,
/// `ActivityTypeVocabularyTest.kt`). This is the fourth, and it exists because
/// the divergence it prevents is invisible: a wrist word that drifts renders
/// perfectly, fails nothing, and is only ever seen by the person wearing the
/// watch in that language.
///
/// The value set is read out of the migration rather than restated, so a
/// migration that widens the CHECK fails this file until the wrist answers
/// for the new value — by offering it, or by recording why it does not.
final class ActivityTypeVocabularyTests: XCTestCase {

    /// Each locale the String Catalog ships, paired with the phone and web
    /// catalogue it answers for. Which catalogue a wrist locale answers for is
    /// a judgement, so the pairing is declared — but the locale SET is held to
    /// the catalog itself by the last test here, so this table cannot fall
    /// behind what the app ships. The phone spells European Portuguese
    /// `app_pt.arb` and the web `pt-PT.ts`, which is why the pairing has to be
    /// stated rather than derived from the name.
    private let localeCatalogues: [(locale: String, arb: String, web: String)] = [
        ("en", "app_en.arb", "en.ts"),
        ("de", "app_de.arb", "de.ts"),
        ("es", "app_es.arb", "es.ts"),
        ("fr", "app_fr.arb", "fr.ts"),
        ("ja", "app_ja.arb", "ja.ts"),
        ("pt-BR", "app_pt_BR.arb", "pt-BR.ts"),
        ("pt-PT", "app_pt.arb", "pt-PT.ts"),
    ]

    /// Values the column admits that the wrist's picker deliberately does not
    /// offer, each with the reason. Wear OS's chip cycles the same four; its
    /// fifth label exists only because `default_activity_type` primes the chip
    /// off the phone's settings bag. This watch is primed from the same bag
    /// now, but through a push that carries only the four the picker cycles.
    /// An entry the CHECK no longer holds fails below, so the register cannot
    /// outlive what it excuses.
    private let notOffered = [
        "stroller": "the phone leaves it off the settings push and `DefaultActivityType.decode` "
            + "refuses it, so a value the runner cannot cycle to is a label nothing would ever render",
    ]

    func testThePickerOffersEveryValueTheColumnAdmitsOrSaysWhyNot() throws {
        let values = try checkValues()
        XCTAssertFalse(values.isEmpty, "parsed an EMPTY value set out of the CHECK constraint")

        let offered = RunActivityType.allCases.map(\.rawValue)
        XCTAssertEqual(
            Set(offered).subtracting(values), [],
            "the picker offers a value `runs_activity_type_check` does not admit — "
                + "a run recorded with it is refused by Postgres 23514 on insert"
        )
        XCTAssertEqual(
            Set(values).subtracting(offered).sorted(), notOffered.keys.sorted(),
            "the CHECK constraint moved. Either offer the new value from the picker, or "
                + "record here why the wrist does not — and drop an entry the column no "
                + "longer holds, which is a reason nobody can see is stale."
        )
    }

    func testEveryOfferedValueCarriesAWordInEveryShippedLocale() throws {
        let catalog = try stringCatalog()
        var checked = 0
        for (locale, _, _) in localeCatalogues {
            var seen: [String: String] = [:]
            for value in RunActivityType.allCases {
                let word = catalogValue(catalog, key: "activityType.\(value.rawValue)", locale: locale)
                XCTAssertNotNil(
                    word,
                    "\(locale) has no word for activity_type \"\(value.rawValue)\". A missing "
                        + "entry is not a build error: the key renders verbatim and every "
                        + "locale shows `activityType.\(value.rawValue)`."
                )
                guard let word, !word.isEmpty else { continue }
                XCTAssertNil(
                    seen[word],
                    "\(locale) labels both \"\(seen[word] ?? "")\" and \"\(value.rawValue)\" "
                        + "as \"\(word)\""
                )
                seen[word] = value.rawValue
                checked += 1
            }
        }
        // Assert the population, not only the property — a value that reached
        // no catalogue at all would satisfy every assertion above.
        XCTAssertEqual(checked, localeCatalogues.count * RunActivityType.allCases.count)
    }

    func testEveryWordIsThePhonesAndTheWebs() throws {
        let root = repoRoot()
        let catalog = try stringCatalog()
        var compared = 0
        for (locale, arbName, webName) in localeCatalogues {
            let arb = try jsonObject(
                at: root.appendingPathComponent("apps/mobile_android/lib/l10n/\(arbName)"))
            let web = try String(
                contentsOf: root.appendingPathComponent("apps/web/src/lib/i18n/locales/\(webName)"),
                encoding: .utf8)
            for value in RunActivityType.allCases {
                let token = value.rawValue
                let wrist = catalogValue(catalog, key: "activityType.\(token)", locale: locale)
                let phone = arb["activityType\(token.prefix(1).uppercased())\(token.dropFirst())"]
                    as? String
                let site = firstGroup(
                    in: web,
                    pattern: "'activityType\\.\(token)'\\s*:\\s*'((?:[^'\\\\]|\\\\.)*)'")?
                    .replacingOccurrences(of: "\\", with: "")
                XCTAssertNotNil(phone, "\(arbName) has no label for \"\(token)\"")
                XCTAssertNotNil(site, "\(webName) has no label for \"\(token)\"")
                XCTAssertEqual(
                    phone, site,
                    "\(arbName) says \"\(phone ?? "")\" for \"\(token)\" where \(webName) says "
                        + "\"\(site ?? "")\". The phone and the web are one vocabulary; the "
                        + "wrist cannot follow both."
                )
                XCTAssertEqual(
                    phone, wrist,
                    "activityType.\(token) is \"\(wrist ?? "")\" in \(locale) where the phone "
                        + "and the web say \"\(phone ?? "")\". One product, one word for one "
                        + "activity — the wrist takes theirs (decisions § 713 / § 1155)."
                )
                compared += 1
            }
        }
        XCTAssertEqual(compared, localeCatalogues.count * RunActivityType.allCases.count)
    }

    /// The table above is the only place a locale's phone and web catalogues
    /// are named, so a locale the app ships and the table omits is a wrist
    /// word nothing compares with theirs.
    func testTheTableCoversExactlyTheLocalesTheCatalogShips() throws {
        let catalog = try stringCatalog()
        var shipped: Set<String> = [catalog["sourceLanguage"] as? String ?? "en"]
        for entry in (catalog["strings"] as? [String: Any] ?? [:]).values {
            if let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] {
                shipped.formUnion(localizations.keys)
            }
        }
        XCTAssertEqual(
            shipped, Set(localeCatalogues.map(\.locale)),
            "the app ships a locale this table does not pair with a phone and web "
                + "catalogue, so its activity words are never compared with theirs — or the "
                + "table names a locale the catalog no longer carries."
        )
    }

    // MARK: - Reading the tree

    /// The authoritative value set, parsed from the migration that declares
    /// `runs_activity_type_check`. Same source the Dart, TypeScript and Kotlin
    /// guards read, so the four cannot disagree about what the column admits.
    private func checkValues() throws -> [String] {
        let dir = repoRoot().appendingPathComponent("apps/backend/supabase/migrations")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".sql") }
            .sorted()
        var found: [String]?
        for name in files {
            let sql = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            guard let list = firstGroup(
                in: sql,
                pattern: "constraint\\s+runs_activity_type_check\\s*check\\s*\\(\\s*activity_type\\s+in\\s*\\(([^)]*)\\)"
            ) else { continue }
            // A later migration replacing the constraint wins.
            found = matches(in: list, pattern: "'([^']+)'")
        }
        let values = try XCTUnwrap(found, "no migration declares runs_activity_type_check")
        return values
    }

    private func stringCatalog() throws -> [String: Any] {
        try jsonObject(
            at: repoRoot().appendingPathComponent(
                "apps/watch_ios/WatchApp/Localizable.xcstrings"))
    }

    private func catalogValue(_ catalog: [String: Any], key: String, locale: String) -> String? {
        let strings = catalog["strings"] as? [String: Any]
        let entry = strings?[key] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]
        let block = localizations?[locale] as? [String: Any]
        let unit = block?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "\(url.lastPathComponent) is not a JSON object"
        )
    }

    private func firstGroup(in text: String, pattern: String) -> String? {
        matches(in: text, pattern: pattern).first
    }

    /// Every first capture group of `pattern` in `text`.
    private func matches(in text: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).compactMap { m in
            Range(m.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // WatchAppTests
            .deletingLastPathComponent() // watch_ios
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repo root
    }
}
