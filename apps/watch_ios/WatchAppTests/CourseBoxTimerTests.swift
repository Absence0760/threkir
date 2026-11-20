import XCTest
import CoreLocation
@testable import WatchApp

/// The live box timer (`CourseBoxTiming.swift`) against the two case tables
/// the server's matcher is held to: `fixtures/segments_gate_cases.json` (the
/// `segments` pair's catalogue matcher cases, box rule § 2589) and
/// `fixtures/park_course_runs.json` (realistic 1 Hz runs over six real park
/// courses, each scored against all six). Streamed fix by fix and settled at
/// the end, the timer must give the batch matcher's effort to the millisecond
/// — the time the course board will show. Plus the live half the batch
/// matcher has no word for: which events fire, when, and what the runner sees
/// and feels.
final class CourseBoxTimerTests: XCTestCase {

    private func repoURL(_ path: String, file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // WatchAppTests
            .deletingLastPathComponent() // watch_ios
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(path)
    }

    private func json(_ path: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: repoURL(path)))
        return try XCTUnwrap(object as? [String: Any])
    }

    private func d(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? .nan }

    private func gate(_ raw: Any?) -> Gate? {
        guard let g = raw as? [String: Any] else { return nil }
        return Gate(lat: d(g["lat"]), lng: d(g["lng"]), bearingDeg: d(g["bearing_deg"]),
                    halfWidthM: d(g["half_width_m"]))
    }

    private func points(_ raw: Any?) -> [CourseBox.Point] {
        (raw as? [[String: Any]] ?? []).map { CourseBox.Point(lat: d($0["lat"]), lng: d($0["lng"])) }
    }

    private func epochMs(_ iso: String) throws -> Double {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try XCTUnwrap(plain.date(from: iso) ?? fractional.date(from: iso)).timeIntervalSince1970 * 1000
    }

    private struct Fix {
        let lat: Double
        let lng: Double
        let tMs: Double
    }

    /// Streams `track` and settles: every event in order, and the settle's.
    private func run(_ timer: CourseBoxTimer, _ track: [Fix]) -> [CourseTimingEvent] {
        var events: [CourseTimingEvent] = []
        for fix in track { events += timer.offer(lat: fix.lat, lng: fix.lng, tMs: fix.tMs) }
        if let last = timer.settle() { events.append(last) }
        return events
    }

    // MARK: - The matcher's own cases

    func testSegmentsGateCasesGiveTheMatchersEffort() throws {
        let fixture = try json("fixtures/segments_gate_cases.json")
        let base = try epochMs(try XCTUnwrap(fixture["base_time"] as? String))
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        var boxCases = 0
        for c in cases {
            let name = c["name"] as? String ?? "?"
            let segment = c["segment"] as? [String: Any] ?? [:]
            guard let start = gate(segment["start_gate"]), let end = gate(segment["end_gate"]) else {
                // No pair of lines: the server times these by its circles,
                // which a wrist never follows, so the timer must refuse them.
                XCTAssertEqual((c["expect"] as? [String: Any])?["matched_by"] as? String, "zone", name)
                continue
            }
            boxCases += 1
            let timer = try XCTUnwrap(CourseBoxTimer(
                startGate: start, endGate: end, distanceM: d(segment["distance_m"]),
                checkpoints: points(segment["checkpoints"])
            ), name)
            // The server's `trackLine`: fixes kept off the line are not read.
            let track = (c["track"] as? [[String: Any]] ?? [])
                .filter { ($0["off_track"] as? Bool) != true }
                .map { Fix(lat: d($0["lat"]), lng: d($0["lng"]), tMs: base + (d($0["t"]) * 1000).rounded()) }
            let events = run(timer, track)

            guard let expect = c["expect"] as? [String: Any] else {
                XCTAssertNil(timer.bestSeconds, "\(name): timed \(timer.bestSeconds ?? 0) s")
                XCTAssertFalse(events.contains { $0.finishSeconds != nil }, "\(name): said Finished!")
                continue
            }
            XCTAssertEqual(expect["matched_by"] as? String, "gate", name)
            let seconds = try XCTUnwrap(timer.bestSeconds, "\(name): no effort")
            XCTAssertEqual(seconds, d(expect["time_seconds"]), accuracy: 0.001, name)
            XCTAssertEqual(Int((timer.bestStartMs! ).rounded()) - Int(base), (expect["started_offset_ms"] as? NSNumber)?.intValue, name)
            // The wrist said "Finished!" with a time, and the fastest one it
            // said is the effort.
            let said = events.compactMap(\.finishSeconds)
            XCTAssertEqual(said.min() ?? -1, seconds, accuracy: 0.001, name)
            XCTAssertEqual(events.first.map { if case .started = $0 { return true } else { return false } }, true,
                           "\(name): timing starts before it finishes")
        }
        XCTAssertEqual(boxCases, 23, "every box case in the table is replayed")
    }

    func testParkCourseRunsAreTimedOnTheirOwnCourseOnly() throws {
        let fixture = try json("fixtures/park_course_runs.json")
        let base = try epochMs(try XCTUnwrap(fixture["base_time"] as? String))
        let courses = try XCTUnwrap(fixture["courses"] as? [[String: Any]])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertEqual(courses.count, 6)
        XCTAssertFalse(cases.isEmpty)

        for c in cases {
            let name = c["name"] as? String ?? "?"
            let track = try decode(try XCTUnwrap(c["track"] as? [String: Any]), base: base)
            let matched = c["matched"] as? [String: Any] ?? [:]
            for course in courses {
                let slug = course["slug"] as? String ?? "?"
                let timer = try XCTUnwrap(CourseBoxTimer(
                    startGate: try XCTUnwrap(gate(course["start_gate"])),
                    endGate: try XCTUnwrap(gate(course["end_gate"])),
                    distanceM: d(course["distance_m"]),
                    checkpoints: points(course["checkpoints"])
                ))
                _ = run(timer, track)
                guard let recorded = matched[slug] as? [String: Any] else {
                    XCTAssertNil(timer.bestSeconds, "\(name) on \(slug): timed \(timer.bestSeconds ?? 0) s")
                    continue
                }
                let seconds = try XCTUnwrap(timer.bestSeconds, "\(name) on \(slug): no effort")
                XCTAssertEqual(seconds, d(recorded["time_seconds"]), accuracy: 0.001, "\(name) on \(slug)")
                XCTAssertEqual(Int(timer.bestStartMs!.rounded()) - Int(base),
                               (recorded["started_offset_ms"] as? NSNumber)?.intValue, "\(name) on \(slug)")
            }
            let want = c["want"] as? [String: Any] ?? [:]
            if want["effort"] as? Bool == true {
                XCTAssertNotNil(matched[c["course"] as? String ?? ""], "\(name): wants an effort on its own course")
            }
        }
    }

    /// The fixture's compact track: micro-degree deltas, one second apart
    /// unless `gaps` says otherwise.
    private func decode(_ track: [String: Any], base: Double) throws -> [Fix] {
        let first = try XCTUnwrap(track["first"] as? [NSNumber]).map(\.intValue)
        let deltas = try XCTUnwrap(track["d"] as? [NSNumber]).map(\.intValue)
        var gaps: [Int: Int] = [:]
        for g in track["gaps"] as? [[NSNumber]] ?? [] { gaps[g[0].intValue] = g[1].intValue }
        var lat = first[0]
        var lng = first[1]
        var t = 0
        var out = [Fix(lat: Double(lat) / 1e6, lng: Double(lng) / 1e6, tMs: base)]
        for i in stride(from: 1, through: deltas.count / 2, by: 1) {
            lat += deltas[2 * i - 2]
            lng += deltas[2 * i - 1]
            t += gaps[i] ?? 1
            out.append(Fix(lat: Double(lat) / 1e6, lng: Double(lng) / 1e6, tMs: base + Double(t) * 1000))
        }
        return out
    }

    // MARK: - The box geometry

    func testBoxCornersAndSharedSpotFollowTheCourseGatesTable() throws {
        let fixture = try json("fixtures/course_gates_cases.json")
        let constants = try XCTUnwrap(fixture["constants"] as? [String: Any])
        XCTAssertEqual(d(constants["boxDepthM"]), CourseBox.depthM)
        XCTAssertEqual(d(constants["sharedSpotM"]), CourseBox.sharedSpotM)
        XCTAssertEqual(d(constants["sharedSpotDeg"]), CourseBox.sharedSpotDeg)
        let tol = d(fixture["degreeTolerance"])
        func camel(_ raw: Any?) -> Gate {
            let g = raw as? [String: Any] ?? [:]
            return Gate(lat: d(g["lat"]), lng: d(g["lng"]), bearingDeg: d(g["bearingDeg"]),
                        halfWidthM: d(g["halfWidthM"]))
        }
        for c in try XCTUnwrap(fixture["boxCorners"] as? [[String: Any]]) {
            let side: CourseBox.Side
            switch c["side"] as? String {
            case "behind": side = .behind
            case "ahead": side = .ahead
            default: side = .centred
            }
            let got = CourseBox.box(camel(c["gate"]), depthM: d(c["depthM"]), side: side,
                                    from: d(c["from"]), to: d(c["to"]))
            let want = points(c["corners"])
            XCTAssertEqual(got.count, want.count)
            for (g, w) in zip(got, want) {
                XCTAssertEqual(g.lat, w.lat, accuracy: tol, c["note"] as? String ?? "")
                XCTAssertEqual(g.lng, w.lng, accuracy: tol, c["note"] as? String ?? "")
            }
        }
        for c in try XCTUnwrap(fixture["sharedSpot"] as? [[String: Any]]) {
            XCTAssertEqual(CourseBox.shareSpot(camel(c["start"]), camel(c["finish"])), c["shared"] as? Bool,
                           c["note"] as? String ?? "")
        }
    }

    // MARK: - Live: what fires, and when

    /// A straight 400 m course due east at 37.5 N: start line at x = 0, finish
    /// line at x = 400 m, both facing east, 15 m half-width.
    private let mPerDegLng = GateConstants.earthRadiusM * Double.pi / 180 * cos(37.5 * Double.pi / 180)
    private func east(_ x: Double) -> Double { -77.5 + x / mPerDegLng }
    private var straightStart: Gate { Gate(lat: 37.5, lng: -77.5, bearingDeg: 90, halfWidthM: 15) }
    private var straightFinish: Gate { Gate(lat: 37.5, lng: east(400), bearingDeg: 90, halfWidthM: 15) }

    /// 4 m/s from `fromX`, one fix a second for `seconds`.
    private func runEast(fromX: Double, seconds: Int, t0: Double = 1_800_000_000_000) -> [Fix] {
        (0...seconds).map { Fix(lat: 37.5, lng: east(fromX + 4 * Double($0)), tMs: t0 + Double($0) * 1000) }
    }

    func testTimingStartsOnLeavingTheStartBoxAndFinishesOnEnteringTheFinishBox() throws {
        let timer = try XCTUnwrap(CourseBoxTimer(startGate: straightStart, endGate: straightFinish, distanceM: 400))
        var started: Int?
        var finished: Int?
        // From 10 m behind the start line to 20 m past the finish.
        for (i, fix) in runEast(fromX: -10, seconds: 107).enumerated() {
            for event in timer.offer(lat: fix.lat, lng: fix.lng, tMs: fix.tMs) {
                switch event {
                case .started: started = started ?? i
                case .finished: finished = finished ?? i
                }
            }
        }
        // x = -10 + 4i crosses 0 between fix 2 and fix 3, and 400 between
        // fix 102 and fix 103: each event fires on the fix that completes the
        // crossing, never earlier.
        XCTAssertEqual(started, 3)
        XCTAssertEqual(finished, 103)
        XCTAssertEqual(try XCTUnwrap(timer.bestSeconds), 100, accuracy: 0.001)
        XCTAssertFalse(timer.isTiming)
        XCTAssertNil(timer.settle(), "a lap already finished is not finished twice")
    }

    func testARunThatStopsShortIsNeverFinished() throws {
        let timer = try XCTUnwrap(CourseBoxTimer(startGate: straightStart, endGate: straightFinish, distanceM: 400))
        let events = run(timer, runEast(fromX: -10, seconds: 60))
        XCTAssertEqual(events.count, 1)
        guard case .started? = events.first else { return XCTFail("timing never started") }
        XCTAssertNil(timer.bestSeconds)
    }

    func testStoppingInsideTheFinishSlackFinishesAtSettle() throws {
        let timer = try XCTUnwrap(CourseBoxTimer(startGate: straightStart, endGate: straightFinish, distanceM: 400))
        // Ends at x = 398: 2 m short of the finish line, inside the 5 m slack.
        var events: [CourseTimingEvent] = []
        for fix in runEast(fromX: -10, seconds: 102) {
            events += timer.offer(lat: fix.lat, lng: fix.lng, tMs: fix.tMs)
        }
        XCTAssertFalse(events.contains { $0.finishSeconds != nil }, "no finish until the run ends")
        let last = try XCTUnwrap(timer.settle())
        // The last stretch within the slack is the final fix alone (fix 101
        // at x = 394 is 6 m short, outside it), so the finish is fix 102's
        // instant, 102 s, against a start crossed at 2.5 s.
        XCTAssertEqual(try XCTUnwrap(last.finishSeconds), 102 - 2.5, accuracy: 0.001)
    }

    func testACourseWithoutAPairOfUsableLinesOrALengthIsNotTimed() {
        XCTAssertNil(CourseBoxTimer(startGate: straightStart, endGate: straightFinish, distanceM: 0))
        XCTAssertNil(CourseBoxTimer(startGate: straightStart, endGate: straightFinish, distanceM: .nan))
        XCTAssertNil(CourseBoxTimer(
            startGate: Gate(lat: .nan, lng: -77.5, bearingDeg: 90, halfWidthM: 15),
            endGate: straightFinish, distanceM: 400))
    }

    // MARK: - What the runner sees and feels

    func testTheDisplayKeepsTheFinishThroughTheNextLapsStart() {
        let finish = CourseTimingEvent.finished(startMs: 0, endMs: 31_330_000)
        var display = CourseTimingDisplay.next(nil, after: [.started(atMs: 0)])
        XCTAssertEqual(display, .timing)
        XCTAssertEqual(CourseTimingDisplay.haptic(for: [.started(atMs: 0)], before: nil), .started)
        XCTAssertNil(CourseTimingDisplay.haptic(for: [.started(atMs: 5)], before: .timing),
                     "a later start while timing does not buzz again")
        XCTAssertEqual(CourseTimingDisplay.haptic(for: [finish, .started(atMs: 1)], before: display), .finished)
        display = CourseTimingDisplay.next(display, after: [finish, .started(atMs: 31_330_000)])
        XCTAssertEqual(display, .finished(seconds: 31_330))
        XCTAssertNil(CourseTimingDisplay.haptic(for: [.started(atMs: 9)], before: display),
                     "no start buzz once a lap has finished")
        XCTAssertEqual(CourseTimingDisplay.clock(seconds: 31_330), "8:42:10")
        XCTAssertEqual(CourseTimingDisplay.clock(seconds: 1296.67), "0:21:36")
        XCTAssertEqual(CourseTimingDisplay.clock(seconds: .nan), "0:00:00")
    }

    func testTheRecorderBuzzesOnceForTheStartAndOnceForTheFinish() throws {
        let wm = WorkoutManager()
        var buzzes: [CourseTimingHaptic] = []
        wm.courseHaptic = { buzzes.append($0) }
        let course = ParkCourse(id: "c1", name: "Straight", distanceMetres: 400,
                                startGate: straightStart, endGate: straightFinish,
                                checkpointLatitudes: [], checkpointLongitudes: [])
        wm.armCourseTiming(course)

        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let fixes = (0...107).map { i -> CLLocation in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: east(-10 + 4 * Double(i))),
                       altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5,
                       timestamp: t0.addingTimeInterval(Double(i)))
        }
        for fix in fixes.prefix(50) { wm.locationManager(CLLocationManager(), didUpdateLocations: [fix]) }
        XCTAssertEqual(wm.courseTiming, .timing)
        XCTAssertEqual(buzzes, [.started])
        wm.locationManager(CLLocationManager(), didUpdateLocations: Array(fixes.dropFirst(50)))
        XCTAssertEqual(wm.courseTiming, .finished(seconds: 100))
        XCTAssertEqual(buzzes, [.started, .finished])
    }

    func testACanopyFixIsNotOnTheLineTheCourseIsTimedBy() throws {
        let wm = WorkoutManager()
        wm.courseHaptic = { _ in }
        wm.armCourseTiming(ParkCourse(id: "c1", name: "Straight", distanceMetres: 400,
                                      startGate: straightStart, endGate: straightFinish,
                                      checkpointLatitudes: [], checkpointLongitudes: []))
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        // Across the start line, but every fix past the 30 m track gate: the
        // server's matcher never reads these, so neither does the wrist.
        let fixes = (0...10).map { i in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: east(-10 + 4 * Double(i))),
                       altitude: 10, horizontalAccuracy: 40, verticalAccuracy: 5,
                       timestamp: t0.addingTimeInterval(Double(i)))
        }
        wm.locationManager(CLLocationManager(), didUpdateLocations: fixes)
        XCTAssertNil(wm.courseTiming)
    }

    func testNoArmedCourseShowsNothing() {
        let wm = WorkoutManager()
        wm.armCourseTiming(nil)
        wm.locationManager(CLLocationManager(), didUpdateLocations: [
            CLLocation(latitude: 37.5, longitude: -77.5),
        ])
        XCTAssertNil(wm.courseTiming)
    }
}
