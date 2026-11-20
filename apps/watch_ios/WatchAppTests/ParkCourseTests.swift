import XCTest
@testable import WatchApp

/// The phone → watch park course push (`park_course`, #1446): what a
/// well-formed payload yields, the explicit clear, and every fail-closed
/// refusal. A course the watch half-read would time the runner by a rule the
/// server does not use and say "Finished!" for a run that gets no time.
final class ParkCourseTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ParkCourseTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func course(_ overrides: [String: Any] = [:], removing: [String] = []) -> [String: Any] {
        var c: [String: Any] = [
            "course_id": "beaver-lake-trail",
            "course_name": "Beaver Lake Trail",
            "course_distance_m": 3595.0,
            "start_gate_lat": 37.386024, "start_gate_lng": -77.584133,
            "start_gate_bearing_deg": 153.1484956563911, "start_gate_half_width_m": 15,
            "end_gate_lat": 37.386024, "end_gate_lng": -77.584133,
            "end_gate_bearing_deg": 191.48459767326835, "end_gate_half_width_m": 15.0,
            "checkpoint_lat": [37.384171, 37.382147],
            "checkpoint_lng": [-77.585807, -77.590548],
        ]
        for (k, v) in overrides { c[k] = v }
        for k in removing { c.removeValue(forKey: k) }
        return c
    }

    func testAWellFormedCourseDecodes() throws {
        guard case let .course(c)? = ParkCourse.push(in: ["park_course": course()]) else {
            return XCTFail("refused a well-formed course")
        }
        XCTAssertEqual(c.id, "beaver-lake-trail")
        XCTAssertEqual(c.name, "Beaver Lake Trail")
        XCTAssertEqual(c.distanceMetres, 3595)
        XCTAssertEqual(c.startGate, Gate(lat: 37.386024, lng: -77.584133, bearingDeg: 153.1484956563911, halfWidthM: 15))
        XCTAssertEqual(c.endGate.bearingDeg, 191.48459767326835)
        XCTAssertEqual(c.checkpoints, [
            CourseBox.Point(lat: 37.384171, lng: -77.585807),
            CourseBox.Point(lat: 37.382147, lng: -77.590548),
        ])
        XCTAssertNotNil(c.makeTimer())
    }

    func testACourseWithNoCheckpointsDecodes() {
        XCTAssertNotNil(ParkCourse.decode(course(["checkpoint_lat": [Double](), "checkpoint_lng": [Double]()])))
    }

    func testAPayloadWithoutTheKeySaysNothing() {
        XCTAssertNil(ParkCourse.push(in: ["route_id": "r1"]))
    }

    func testAnEmptyDictionaryClears() {
        XCTAssertEqual(ParkCourse.push(in: ["park_course": [String: Any]()]), .clear)
    }

    func testEveryRefusalClearsRatherThanHalfLoading() {
        let refused: [[String: Any]] = [
            course(["course_id": ""]),
            course(removing: ["course_id"]),
            course(removing: ["course_name"]),
            course(["course_distance_m": 0.0]),
            course(["course_distance_m": -5.0]),
            course(["course_distance_m": Double.nan]),
            course(["course_distance_m": "3595"]),
            course(removing: ["end_gate_lat"]),
            course(removing: ["start_gate_bearing_deg"]),
            course(["start_gate_half_width_m": 0.0]),
            course(["end_gate_lat": Double.infinity]),
            course(["start_gate_lat": 90.0]),
            course(["checkpoint_lat": [37.38]]),
            course(removing: ["checkpoint_lng"]),
            course(["checkpoint_lat": [37.38, Double.nan], "checkpoint_lng": [-77.5, -77.5]]),
            course(["checkpoint_lat": [37.38, "x"], "checkpoint_lng": [-77.5, -77.5]]),
            course([
                "checkpoint_lat": [Double](repeating: 37.38, count: ParkCourse.maxCheckpoints + 1),
                "checkpoint_lng": [Double](repeating: -77.5, count: ParkCourse.maxCheckpoints + 1),
            ]),
        ]
        for (i, c) in refused.enumerated() {
            XCTAssertNil(ParkCourse.decode(c), "case \(i) decoded")
            XCTAssertEqual(ParkCourse.push(in: ["park_course": c]), .clear, "case \(i)")
        }
        XCTAssertEqual(ParkCourse.push(in: ["park_course": "beaver"]), .clear)
    }

    func testTheStoreKeepsAndClearsTheCourse() throws {
        XCTAssertNil(ParkCourseStore.load(defaults: defaults))
        let push = try XCTUnwrap(ParkCourse.push(in: ["park_course": course()]))
        ParkCourseStore.apply(push, defaults: defaults)
        guard case let .course(sent) = push else { return XCTFail() }
        XCTAssertEqual(ParkCourseStore.load(defaults: defaults), sent)
        ParkCourseStore.apply(.clear, defaults: defaults)
        XCTAssertNil(ParkCourseStore.load(defaults: defaults))
    }

    func testAnUnreadableStoreIsNoCourse() {
        defaults.set(Data("not json".utf8), forKey: "park_course_v1")
        XCTAssertNil(ParkCourseStore.load(defaults: defaults))
    }
}
