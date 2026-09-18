import XCTest
@testable import WatchApp

/// The pedometer's per-run baseline, and the survival of its count through a
/// crash.
///
/// `CMPedometer` cannot be driven from a test — a simulator has no motion
/// hardware and neither does CI — so the arithmetic that turns a cumulative
/// reading into THIS run's steps lives in `PedometerMath` and is pinned here,
/// the way Wear OS pins the same function in `PedometerMathTest.kt`. What no
/// test on this tier can reach is the sensor itself; see the PR body and
/// `docs/product/parity.md` for what remains device-gated.
final class PedometerTests: XCTestCase {

    // MARK: - Baseline

    func testFirstReadingBecomesTheBaselineSoTheRunOpensAtZero() {
        let reading = PedometerMath.stepsSinceBaseline(currentReading: 148_902, baseline: nil)
        XCTAssertEqual(reading.baseline, 148_902)
        XCTAssertEqual(
            reading.stepsThisRun, 0,
            "Without the baseline the run's first sample is the device's lifetime total, " +
                "and `metadata.steps` becomes a number about the watch rather than the run"
        )
    }

    func testSubsequentReadingsSubtractTheBaseline() {
        let first = PedometerMath.stepsSinceBaseline(currentReading: 148_902, baseline: nil)
        let later = PedometerMath.stepsSinceBaseline(
            currentReading: 152_302, baseline: first.baseline
        )
        XCTAssertEqual(later.baseline, 148_902, "The baseline is set once per run, not per sample")
        XCTAssertEqual(later.stepsThisRun, 3400)
    }

    func testAReadingBelowTheBaselineFloorsAtZero() {
        let reading = PedometerMath.stepsSinceBaseline(currentReading: 10, baseline: 42)
        XCTAssertEqual(
            reading.stepsThisRun, 0,
            "A cumulative counter should never fall, but a negative delta reaching the " +
                "summary renders as \"-32 steps\" and reaches the row as a negative count"
        )
        XCTAssertEqual(reading.baseline, 42, "A wild reading must not re-anchor the run")
    }

    // MARK: - Crash recovery

    func testStepCountSurvivesTheCheckpointRoundTrip() {
        let id = "steps-\(UUID().uuidString.lowercased())"
        let store = CheckpointStore(runId: id)
        defer { store.clear() }
        store.write(checkpoint: RunCheckpoint(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMetres: 4200,
            activeDurationSeconds: 1500,
            pausedIntervalSeconds: 0,
            trackPointCount: 200,
            cacheFileURL: store.trackFileURL,
            averageBPM: nil,
            hrCoverage: nil,
            steps: 5123,
            laps: nil
        ))
        XCTAssertEqual(CheckpointStore.peekCheckpoint()?.steps, 5123)
    }

    func testRecoveredRunKeepsItsStepCount() {
        let id = "steps-recover-\(UUID().uuidString.lowercased())"
        let store = CheckpointStore(runId: id)
        store.appendTrackPoints([
            TrackPointRecord(lat: 51.45, lng: -0.19, ele: nil, ts: "2026-04-15T07:30:01Z"),
        ])
        store.closeAppendHandle()
        defer { store.clear() }
        store.write(checkpoint: RunCheckpoint(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMetres: 4200,
            activeDurationSeconds: 1500,
            pausedIntervalSeconds: 0,
            trackPointCount: 1,
            cacheFileURL: store.trackFileURL,
            averageBPM: nil,
            hrCoverage: nil,
            steps: 5123,
            laps: nil
        ))

        let wm = WorkoutManager()
        XCTAssertEqual(
            wm.recoverRun()?.steps, 5123,
            "A crash-recovered run that keeps its distance and drops its steps uploads " +
                "silently short, with nothing on the row saying a pedometer ever ran (#389)"
        )
        XCTAssertEqual(wm.steps, 5123)
    }

    func testCheckpointFromABuildWithoutStepsDecodesAsUnmeasured() throws {
        let json = """
        {"version":1,"id":"old","startedAt":"2026-04-15T07:30:00Z","distanceMetres":1000,
         "activeDurationSeconds":300,"pausedIntervalSeconds":0,"trackPointCount":4,
         "cacheFileURL":"file:///tmp/old.ndjson"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cp = try decoder.decode(RunCheckpoint.self, from: Data(json.utf8))
        XCTAssertNil(
            cp.steps,
            "Absent must stay absent: a 0 here would claim the runner stood still for " +
                "the whole recovered run"
        )
    }

    // MARK: - What reaches the row

    /// A measured count, never an assumed one — the same rule `hr_coverage`
    /// carries, and for the same reason: a fabricated measurement is worse
    /// than the absence it replaces.
    func testSyncRunWritesStepsOnlyFromAPositiveMeasuredCount() throws {
        let contentView = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WatchApp/ContentView.swift")
        let source = String(decoding: try Data(contentsOf: contentView), as: UTF8.self)
        XCTAssertTrue(
            source.contains(#"if let count = run.steps, count > 0 { metadata["steps"] = count }"#),
            """
            `metadata.steps` must be written only from a non-nil, positive count. An \
            unconditional write sends 0 from every watch with no pedometer grant, and \
            `runFromWatchPayload` would forward it onto the row as a run of no steps.
            """
        )
    }
}
