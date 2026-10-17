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
