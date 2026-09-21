import XCTest
@testable import WatchApp

/// The pure shaping behind `RouteGuidanceView`. The three-way status is the
/// point of the suite: a runner who is shown nothing must be able to tell
/// "on the line" from "the watch has lost the line", and a latched off-route
/// alert must survive a fix the geometry refused.
final class RouteGuidanceTests: XCTestCase {
    private var savedUnit: String?

    override func setUp() {
        super.setUp()
        savedUnit = UserDefaults.standard.string(forKey: "preferred_unit")
        UserDefaults.standard.set("km", forKey: "preferred_unit")
    }

    override func tearDown() {
        if let savedUnit {
            UserDefaults.standard.set(savedUnit, forKey: "preferred_unit")
        } else {
            UserDefaults.standard.removeObject(forKey: "preferred_unit")
        }
        super.tearDown()
    }

    // MARK: - Status

    func testOnRouteWhenADeviationIsKnownAndTheLatchIsClear() {
        XCTAssertEqual(
            RouteGuidance.status(isOffRoute: false, deviationMetres: 12),
            .onRoute)
        XCTAssertEqual(
            RouteGuidance.status(isOffRoute: false, deviationMetres: 0),
            .onRoute)
    }

    func testUnknownWhenThereIsNoProjection() {
        XCTAssertEqual(
            RouteGuidance.status(isOffRoute: false, deviationMetres: nil),
            .unknown)
    }

    func testOffRouteOutranksAMissingDeviation() {
        // The navigator keeps the latch across a non-finite fix; the display
        // must not downgrade a live alert to "unknown" for that one sample.
        XCTAssertEqual(
            RouteGuidance.status(isOffRoute: true, deviationMetres: nil),
            .offRoute)
        XCTAssertEqual(
            RouteGuidance.status(isOffRoute: true, deviationMetres: 62),
            .offRoute)
    }

    // MARK: - Remaining

    /// The locale is named, not inherited: the rendering carries a decimal
    /// separator and a unit word, and asserting an English one against
    /// whatever language the simulator was left in is what made this test
    /// red on a Japanese watch (`1.00 マイル`) and green everywhere CI looked.
    func testRemainingTextUsesThePreferredUnit() {
        let enUS = Locale(identifier: "en_US")
        XCTAssertEqual(RouteGuidance.remainingText(metres: 4210, locale: enUS), "4.21 km")

        UserDefaults.standard.set("mi", forKey: "preferred_unit")
        XCTAssertEqual(RouteGuidance.remainingText(metres: 1609.344, locale: enUS), "1.00 miles")
    }

    func testRemainingTextIsNilWithoutAProjection() {
        XCTAssertNil(RouteGuidance.remainingText(metres: nil))
        XCTAssertNil(RouteGuidance.remainingText(metres: .nan))
        XCTAssertNil(RouteGuidance.remainingText(metres: -1))
    }

    func testRemainingTextRendersZeroRatherThanHidingTheFinish() {
        let s = RouteGuidance.remainingText(metres: 0)
        XCTAssertNotNil(s)
        XCTAssertTrue(s!.hasPrefix("0"), "Got: \(s!)")
    }

    // MARK: - Deviation

    func testDeviationTextStaysMetricInBothUnitModes() {
        let km = RouteGuidance.deviationText(metres: 62.4)
        XCTAssertNotNil(km)
        XCTAssertTrue(km!.contains("62"), "Got: \(km!)")

        UserDefaults.standard.set("mi", forKey: "preferred_unit")
        let mi = RouteGuidance.deviationText(metres: 62.4)
        XCTAssertEqual(mi, km, "A deviation is metres in mi-mode too")
    }

    func testDeviationTextRoundsToWholeMetres() {
        let s = RouteGuidance.deviationText(metres: 41.6)
        XCTAssertNotNil(s)
        XCTAssertTrue(s!.contains("42"), "Got: \(s!)")
        XCTAssertFalse(s!.contains("41.6"), "Got: \(s!)")
    }

    func testDeviationTextIsNilWithoutADeviation() {
        XCTAssertNil(RouteGuidance.deviationText(metres: nil))
        XCTAssertNil(RouteGuidance.deviationText(metres: .infinity))
        XCTAssertNil(RouteGuidance.deviationText(metres: -5))
    }
}
