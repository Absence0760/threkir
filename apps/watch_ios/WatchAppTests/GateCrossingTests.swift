import XCTest
@testable import WatchApp

/// Replays `fixtures/gate_crossing_cases.json` — the `gate_crossing v1` case
/// table the web, phone and Wear OS suites read — through the Swift port in
/// `GateCrossing.swift`. Every section of the file is run (`projection`,
/// `crossings`), and an unknown one fails, as the file's schema asks of
/// every reader.
final class GateCrossingTests: XCTestCase {

    private func loadFixture(file: StaticString = #filePath) throws -> [String: Any] {
        let url = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // WatchAppTests
            .deletingLastPathComponent() // watch_ios
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("fixtures/gate_crossing_cases.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(object as? [String: Any])
    }

    /// A number, or one of the three strings JSON spells the IEEE specials
    /// with in this file.
    private func num(_ value: Any?) -> Double {
        switch value {
        case let s as String:
            switch s {
            case "NaN": return .nan
            case "Infinity": return .infinity
            case "-Infinity": return -.infinity
            default: XCTFail("not a number: \(s)"); return .nan
            }
        case let n as NSNumber: return n.doubleValue
        default: XCTFail("not a number: \(String(describing: value))"); return .nan
        }
    }

    private func gate(_ raw: Any?) -> Gate {
        let g = raw as? [String: Any] ?? [:]
        return Gate(lat: num(g["lat"]), lng: num(g["lng"]), bearingDeg: num(g["bearingDeg"]),
                    halfWidthM: num(g["halfWidthM"]))
    }

    /// `{lat, lng}` as given, or `{eastM, northM}` from the gate centre.
    private func position(_ raw: [String: Any], gate: Gate) -> (lat: Double, lng: Double) {
        if raw["lat"] != nil { return (num(raw["lat"]), num(raw["lng"])) }
        let k = GateConstants.earthRadiusM * Double.pi / 180
        return (
            gate.lat + num(raw["northM"]) / k,
            gate.lng + num(raw["eastM"]) / (k * cos(gate.lat * Double.pi / 180))
        )
    }

    func testTheConstantsAreTheFixtures() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture["spec"] as? String, "gate_crossing v1")
        let c = try XCTUnwrap(fixture["constants"] as? [String: Any])
        XCTAssertEqual(num(c["EARTH_RADIUS_M"]), GateConstants.earthRadiusM)
        XCTAssertEqual(num(c["MAX_GAP_S"]), GateConstants.maxGapS)
        XCTAssertEqual(num(c["MAX_HOP_M"]), GateConstants.maxHopM)
        XCTAssertEqual(num(c["REJECT_GAP_S"]), GateConstants.rejectGapS)
        XCTAssertEqual(num(c["HALF_WIDTH_RACE_M"]), GateConstants.halfWidthRaceM)
        XCTAssertEqual(num(c["HALF_WIDTH_SEGMENT_M"]), GateConstants.halfWidthSegmentM)
    }

    func testEverySectionIsOneThisReaderRuns() throws {
        let fixture = try loadFixture()
        let known: Set<String> = [
            "spec", "reference", "readers", "schema", "constants", "t0EpochMs",
            "distanceToleranceM", "timeToleranceS", "fractionTolerance", "projection", "crossings",
        ]
        XCTAssertEqual(Set(fixture.keys).subtracting(known), [], "a section this port does not run")
    }

    func testProjection() throws {
        let fixture = try loadFixture()
        let tol = num(fixture["distanceToleranceM"])
        let cases = try XCTUnwrap(fixture["projection"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let name = c["name"] as? String ?? "?"
            let g = gate(c["gate"])
            let p = position(c["point"] as? [String: Any] ?? [:], gate: g)
            let got = gateProjection(g, p.lat, p.lng)
            let expect = c["expect"] as? [String: Any] ?? [:]
            XCTAssertEqual(got.s, num(expect["s"]), accuracy: tol, name)
            XCTAssertEqual(got.u, num(expect["u"]), accuracy: tol, name)
        }
    }

    func testCrossingsStreamedSettledAndBatched() throws {
        let fixture = try loadFixture()
        let t0 = num(fixture["t0EpochMs"])
        let distTol = num(fixture["distanceToleranceM"])
        let timeTol = num(fixture["timeToleranceS"])
        let fracTol = num(fixture["fractionTolerance"])
        let cases = try XCTUnwrap(fixture["crossings"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)

        for c in cases {
            let name = c["name"] as? String ?? "?"
            let g = gate(c["gate"])
            var options = GateCrossingOptions()
            if let o = c["options"] as? [String: Any] {
                options = GateCrossingOptions(maxGapS: num(o["maxGapS"]), maxHopM: num(o["maxHopM"]),
                                              rejectGapS: num(o["rejectGapS"]))
            }
            func fixes(_ raw: Any?) -> [GateFix] {
                (raw as? [[String: Any]] ?? []).map { f in
                    let p = position(f, gate: g)
                    return GateFix(lat: p.lat, lng: p.lng, tMs: t0 + num(f["atS"]) * 1000,
                                   coveredM: num(f["coveredM"]))
                }
            }
            let track = fixes(c["fixes"])
            let expect = c["expect"] as? [[String: Any]] ?? []

            func check(_ got: GateCrossing, _ want: [String: Any], _ label: String) {
                XCTAssertEqual(got.direction.rawValue, want["direction"] as? String, label)
                XCTAssertEqual(got.fraction, num(want["fraction"]), accuracy: fracTol, label)
                XCTAssertEqual((got.tMs - t0) / 1000, num(want["atS"]), accuracy: timeTol, label)
                XCTAssertEqual(got.coveredM, num(want["coveredM"]), accuracy: distTol, label)
                XCTAssertEqual(got.offsetM, num(want["offsetM"]), accuracy: distTol, label)
                XCTAssertEqual(got.gapped, want["gapped"] as? Bool, label)
            }

            let detector = GateCrossingDetector(g, options: options)
            for (i, fix) in track.enumerated() {
                let got = detector.offer(fix)
                if let want = expect.first(where: { ($0["afterFix"] as? Int) == i }) {
                    guard let got else { XCTFail("\(name): no crossing after fix \(i)"); continue }
                    check(got, want, "\(name) streamed after fix \(i)")
                } else {
                    XCTAssertNil(got, "\(name): unexpected crossing after fix \(i)")
                }
            }
            let settled = detector.settle()
            XCTAssertEqual(settled.count, expect.count, name)
            for (got, want) in zip(settled, expect) { check(got, want, "\(name) settled") }
            for fix in fixes(c["fixesAfterSettle"]) {
                XCTAssertNil(detector.offer(fix), "\(name): offered after settle")
            }
            XCTAssertEqual(detector.settle().count, expect.count, "\(name): settle unchanged")

            let batch = crossingsOf(track, g, options: options)
            XCTAssertEqual(batch.count, expect.count, "\(name) batch")
            for (got, want) in zip(batch, expect) { check(got, want, "\(name) batch") }
        }
    }
}
