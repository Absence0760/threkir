import XCTest
@testable import WatchApp

/// The Swift step runner against the phone's reference runner, through the
/// shared vectors (`fixtures/watch_workout_payload.json` § runner_vectors),
/// which the Dart runner (`workout_runner_vectors_test.dart`) and the Kotlin
/// port (`WorkoutRunnerTest.kt`) replay too.
final class WatchWorkoutRunnerTests: XCTestCase {

    private func workout(_ steps: [PushedStep], unpaced: Bool = false) -> PushedWorkout {
        PushedWorkout(planWorkoutId: "pw-1", scheduledDate: "2026-10-16", workoutKind: "interval", unpaced: unpaced, steps: steps)
    }

    private func step(_ o: [String: Any]) throws -> PushedStep {
        PushedStep(
            kind: try XCTUnwrap(WorkoutStepKind(rawValue: o["kind"] as? String ?? "")),
            repIndex: o["rep_index"] as? Int,
            repTotal: o["rep_total"] as? Int,
            distanceMetres: o["distance_m"] as? Int,
            durationSeconds: o["duration_s"] as? Int,
            paceSecondsPerKm: try XCTUnwrap(o["pace_s_per_km"] as? Int),
            toleranceSecondsPerKm: try XCTUnwrap(o["tolerance_s_per_km"] as? Int)
        )
    }

    private func token(_ e: WatchWorkoutEvent) -> String? {
        switch e {
        case .transition(_, let current): return "transition:\(current)"
        case .warning: return "warning"
        case .complete: return "complete"
        case .paceDrift: return nil
        }
    }

    private func number(_ v: Any?) -> Double? {
        (v as? NSNumber)?.doubleValue
    }

    func testTheSharedVectorsReplayToTheReferenceRunnersResults() throws {
        let vectors = try XCTUnwrap(PushedWorkoutTests.fixture()["runner_vectors"] as? [[String: Any]])
        XCTAssertFalse(vectors.isEmpty)
        for v in vectors {
            let name = v["name"] as? String ?? "?"
            let steps = try XCTUnwrap(v["steps"] as? [[String: Any]]).map(step)
            let runner = WatchWorkoutRunner(workout: workout(steps))
            for t in try XCTUnwrap(v["ticks"] as? [[String: Any]]) {
                var events = runner.onTotals(
                    distanceMetres: try XCTUnwrap(number(t["distance_m"])),
                    elapsedSeconds: try XCTUnwrap(number(t["elapsed_s"])),
                    now: 0
                )
                if t["skip"] as? Bool == true { events += runner.skipStep() }
                XCTAssertEqual(events.compactMap(token), t["events"] as? [String], "\(name) \(t)")
                XCTAssertEqual(runner.currentIndex, t["index_after"] as? Int, "\(name) \(t)")
            }
            let want = try XCTUnwrap(v["results"] as? [[String: Any]])
            let got = runner.snapshotResults()
            XCTAssertEqual(got.count, want.count, name)
            for (i, w) in want.enumerated() where i < got.count {
                XCTAssertEqual(got[i].stepIndex, w["step_index"] as? Int, "\(name) \(i)")
                XCTAssertEqual(got[i].kind, w["kind"] as? String, "\(name) \(i)")
                XCTAssertEqual(got[i].status, w["status"] as? String, "\(name) \(i)")
                XCTAssertEqual(got[i].durationSeconds, w["duration_s"] as? Int, "\(name) \(i)")
                XCTAssertEqual(got[i].actualPaceSecondsPerKm, w["actual_pace_sec_per_km"] as? Int, "\(name) \(i)")
                XCTAssertEqual(got[i].actualDistanceMetres, try XCTUnwrap(number(w["actual_distance_m"])), accuracy: 1e-6, "\(name) \(i)")
            }
            XCTAssertEqual(runner.adherence(), v["adherence"] as? String, name)
        }
    }

    private let rep = PushedStep(kind: .rep, repIndex: 1, repTotal: 1, distanceMetres: 1000, durationSeconds: nil, paceSecondsPerKm: 240, toleranceSecondsPerKm: 10)

    func testPaceDriftFiresOnAPacedStepAndIsRateLimitedTo45s() {
        let runner = WatchWorkoutRunner(workout: workout([rep]))
        _ = runner.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        let first = runner.onTotals(distanceMetres: 100, elapsedSeconds: 40, now: 40)
        XCTAssertEqual(first, [.paceDrift(index: 0, ahead: false, deltaSecondsPerKm: 160)])
        XCTAssertEqual(runner.onTotals(distanceMetres: 110, elapsedSeconds: 44, now: 44), [])
        XCTAssertTrue(runner.onTotals(distanceMetres: 300, elapsedSeconds: 120, now: 85).contains {
            if case .paceDrift = $0 { return true }; return false
        })
    }

    func testAStandingStartIsNotGradedUntil50mIn20s() {
        // Issue #1300: 19 m in 15 s read way behind under the old 5 m / 1 s gate.
        let slow = WatchWorkoutRunner(workout: workout([rep]))
        _ = slow.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        XCTAssertEqual(slow.onTotals(distanceMetres: 19, elapsedSeconds: 15, now: 15), [])
        XCTAssertEqual(slow.onTotals(distanceMetres: 49, elapsedSeconds: 40, now: 40), [])
        XCTAssertEqual(slow.onTotals(distanceMetres: 50, elapsedSeconds: 40, now: 40),
                       [.paceDrift(index: 0, ahead: false, deltaSecondsPerKm: 560)])

        let fast = WatchWorkoutRunner(workout: workout([rep]))
        _ = fast.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        // 100 m clears the distance floor; 19 s is short of the time floor.
        XCTAssertEqual(fast.onTotals(distanceMetres: 100, elapsedSeconds: 19, now: 19), [])
        // A feed only counts once it moves the distance, as on the phone, so
        // the 20 s sample has to carry new metres: 120 m in 20 s = 167 s/km.
        XCTAssertEqual(fast.onTotals(distanceMetres: 120, elapsedSeconds: 20, now: 20),
                       [.paceDrift(index: 0, ahead: true, deltaSecondsPerKm: 73)])
    }

    func testDriftReadsTheStepsTrailing200mNotItsWholeAverage() {
        // Issue #1300: a slow first 50 m kept the cumulative average way behind
        // long after the runner reached the target.
        let steady = PushedStep(kind: .steady, repIndex: nil, repTotal: nil, distanceMetres: 8047, durationSeconds: nil, paceSecondsPerKm: 348, toleranceSecondsPerKm: 10)
        let runner = WatchWorkoutRunner(workout: workout([steady]))
        _ = runner.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        XCTAssertFalse(runner.onTotals(distanceMetres: 50, elapsedSeconds: 40, now: 40).isEmpty)
        // Until the step passes 250 m its window still holds the slow start.
        for i in 1...6 {
            _ = runner.onTotals(distanceMetres: 50 + Double(i) * 28.736, elapsedSeconds: 40 + Double(i) * 10, now: 40 + Double(i) * 10)
        }
        var later: [WatchWorkoutEvent] = []
        for i in 7...21 {
            later += runner.onTotals(distanceMetres: 50 + Double(i) * 28.736, elapsedSeconds: 40 + Double(i) * 10, now: 40 + Double(i) * 10)
        }
        // The average stays way behind (383 s/km at the end); the last 200 m read 348.
        XCTAssertFalse(later.contains { if case .paceDrift = $0 { return true }; return false })
    }

    func testTheDriftWindowRestartsWithEachStep() {
        let shortRep = PushedStep(kind: .rep, repIndex: 1, repTotal: 1, distanceMetres: 400, durationSeconds: nil, paceSecondsPerKm: 240, toleranceSecondsPerKm: 10)
        let recovery = PushedStep(kind: .recovery, repIndex: nil, repTotal: nil, distanceMetres: 400, durationSeconds: nil, paceSecondsPerKm: 400, toleranceSecondsPerKm: 10)
        let runner = WatchWorkoutRunner(workout: workout([shortRep, recovery]))
        _ = runner.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        for i in 1...24 {
            _ = runner.onTotals(distanceMetres: Double(i) * 400 / 24, elapsedSeconds: Double(i) * 4, now: Double(i) * 4)
        }
        XCTAssertEqual(runner.currentIndex, 1)
        // The recovery at its own 400 s/km; a window reaching into the rep would read fast.
        var events: [WatchWorkoutEvent] = []
        for i in 1...6 {
            events += runner.onTotals(distanceMetres: 400 + Double(i) * 10, elapsedSeconds: 96 + Double(i) * 4, now: 96 + Double(i) * 4)
        }
        XCTAssertFalse(events.contains { if case .paceDrift = $0 { return true }; return false })
    }

    func testACarriedOvershootIsTimedFromTheNewStepsOwnStart() {
        let shortRep = PushedStep(kind: .rep, repIndex: 1, repTotal: 1, distanceMetres: 100, durationSeconds: nil, paceSecondsPerKm: 240, toleranceSecondsPerKm: 10)
        let steady = PushedStep(kind: .steady, repIndex: nil, repTotal: nil, distanceMetres: 400, durationSeconds: nil, paceSecondsPerKm: 240, toleranceSecondsPerKm: 10)
        let runner = WatchWorkoutRunner(workout: workout([shortRep, steady]))
        _ = runner.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        // 150 m in 45 s crosses the rep and carries 50 m and 15 s into the steady.
        _ = runner.onTotals(distanceMetres: 150, elapsedSeconds: 45, now: 45)
        XCTAssertEqual(runner.currentIndex, 1)
        XCTAssertEqual(runner.onTotals(distanceMetres: 160, elapsedSeconds: 48, now: 48), [])
        // 70 m in 21 s of the step = 300 s/km, 60 behind a 10 s tolerance.
        XCTAssertEqual(runner.onTotals(distanceMetres: 170, elapsedSeconds: 51, now: 51),
                       [.paceDrift(index: 1, ahead: false, deltaSecondsPerKm: 60)])
    }

    func testTicksBetweenFixesDoNotReadAsASlowdown() {
        let steady = PushedStep(kind: .steady, repIndex: nil, repTotal: nil, distanceMetres: 1000, durationSeconds: nil, paceSecondsPerKm: 300, toleranceSecondsPerKm: 10)
        let runner = WatchWorkoutRunner(workout: workout([steady]))
        _ = runner.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        for i in 1...10 {
            _ = runner.onTotals(distanceMetres: Double(i) * 20, elapsedSeconds: Double(i) * 6, now: Double(i) * 6)
        }
        // A 6 s GPS hiccup: 200 m over 66 s would read 330 s/km, way behind.
        var ticks: [WatchWorkoutEvent] = []
        for s in 61...66 {
            ticks += runner.onTotals(distanceMetres: 200, elapsedSeconds: Double(s), now: Double(s))
        }
        XCTAssertFalse(ticks.contains { if case .paceDrift = $0 { return true }; return false })
    }

    func testAWalkRunSessionNeverGradesPace() {
        let runner = WatchWorkoutRunner(workout: workout([rep], unpaced: true))
        _ = runner.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        XCTAssertEqual(runner.onTotals(distanceMetres: 100, elapsedSeconds: 40, now: 40), [])
    }

    func testSkipBeforeAnyTotalsDoesNothing() {
        let runner = WatchWorkoutRunner(workout: workout([rep]))
        XCTAssertEqual(runner.skipStep(), [])
        XCTAssertEqual(runner.currentIndex, 0)
    }

    func testTheStepInProgressIsASkippedRowSoACrashKeepsTheReview() {
        let runner = WatchWorkoutRunner(workout: workout([rep, rep]))
        _ = runner.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        _ = runner.onTotals(distanceMetres: 400, elapsedSeconds: 100, now: 0)
        let review = runner.review()
        XCTAssertEqual(review.planWorkoutId, "pw-1")
        XCTAssertEqual(review.adherence, "partial")
        XCTAssertEqual(review.steps.map(\.status), ["skipped"])
        XCTAssertEqual(review.steps.first?.actualDistanceMetres, 400)
    }

    func testTheViewCountsDownOnTheStepsOwnAxis() {
        let timed = PushedStep(kind: .recovery, repIndex: 1, repTotal: 1, distanceMetres: nil, durationSeconds: 90, paceSecondsPerKm: 390, toleranceSecondsPerKm: 10)
        let runner = WatchWorkoutRunner(workout: workout([rep, timed]))
        _ = runner.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        _ = runner.onTotals(distanceMetres: 250, elapsedSeconds: 60, now: 0)
        XCTAssertEqual(runner.view().remainingMetres ?? -1, 750, accuracy: 1e-9)
        XCTAssertNil(runner.view().remainingSeconds)
        _ = runner.onTotals(distanceMetres: 1000, elapsedSeconds: 240, now: 0)
        _ = runner.onTotals(distanceMetres: 1050, elapsedSeconds: 270.5, now: 0)
        XCTAssertEqual(runner.view().remainingSeconds, 60)
        XCTAssertNil(runner.view().remainingMetres)
        _ = runner.onTotals(distanceMetres: 1100, elapsedSeconds: 330, now: 0)
        XCTAssertTrue(runner.isComplete)
        XCTAssertNil(runner.view().step)
        XCTAssertFalse(runner.ownsPaceCues)
    }

    func testTheEnvelopeRowsArePlistSafeAndOmitAnUnmeasuredPace() {
        let runner = WatchWorkoutRunner(workout: workout([rep]))
        _ = runner.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        _ = runner.onTotals(distanceMetres: 2, elapsedSeconds: 0.5, now: 0)
        let rows = runner.review().steps.map(\.envelopeValue)
        XCTAssertTrue(PropertyListSerialization.propertyList(rows, isValidFor: .binary))
        XCTAssertNil(rows.first?["actual_pace_sec_per_km"])
        XCTAssertEqual(rows.first?["step_index"] as? Int, 0)
    }

    func testTheRecordEncodesTheRegistrysKeysAndOmitsAnUnmeasuredPace() throws {
        let runner = WatchWorkoutRunner(workout: workout([rep]))
        _ = runner.onTotals(distanceMetres: 0, elapsedSeconds: 0, now: 0)
        _ = runner.onTotals(distanceMetres: 2, elapsedSeconds: 0.5, now: 0)
        let record = try XCTUnwrap(runner.review().steps.first)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        XCTAssertEqual(
            Set(object?.keys.map { $0 } ?? []),
            ["step_index", "kind", "rep_index", "rep_total", "target_distance_m", "actual_distance_m",
             "target_pace_sec_per_km", "tolerance_sec_per_km", "duration_s", "status"]
        )
        XCTAssertEqual(Set(object?.keys.map { $0 } ?? []), Set(record.envelopeValue.keys))
        XCTAssertEqual(try JSONDecoder().decode(WorkoutStepResultRecord.self, from: JSONEncoder().encode(record)), record)
    }

    func testOneCuePerFeedMostImportantFirst() {
        XCTAssertNil(WatchWorkoutCue.cue(for: [.transition(previous: -1, current: 0)]))
        XCTAssertEqual(WatchWorkoutCue.cue(for: [.warning(index: 0), .transition(previous: 0, current: 1), .transition(previous: 1, current: 2)]), .step)
        XCTAssertEqual(WatchWorkoutCue.cue(for: [.warning(index: 2), .complete]), .complete)
        XCTAssertEqual(WatchWorkoutCue.cue(for: [.warning(index: 1)]), .stepEnding)
        XCTAssertEqual(WatchWorkoutCue.cue(for: [.paceDrift(index: 0, ahead: false, deltaSecondsPerKm: 40)]), .paceAlert(tooSlow: true))
        XCTAssertEqual(WatchWorkoutCue.cue(for: [.paceDrift(index: 0, ahead: true, deltaSecondsPerKm: 40)]), .paceAlert(tooSlow: false))
        XCTAssertEqual(WatchWorkoutCue.cue(for: [.paceDrift(index: 0, ahead: false, deltaSecondsPerKm: 40), .transition(previous: 0, current: 1)]), .step)
        XCTAssertNil(WatchWorkoutCue.cue(for: []))
    }
}
