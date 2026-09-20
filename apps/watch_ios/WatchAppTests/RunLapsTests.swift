import XCTest
@testable import WatchApp

/// The lap-split contract, and its survival through a crash.
///
/// `RunLaps.splits` is the watchOS half of a cross-client shape: the same
/// `runs.metadata.laps` rows are produced by Wear OS's `buildFinishedLapsList`
/// and read by one phone and one web run-detail view, so the per-lap deltas,
/// the cumulative-BEFORE `start_offset_s`, the 1-based index and the
/// trailing-partial gate are pinned here rather than left to the view that
/// renders them. The Wear OS twin of this suite is `FinishedLapsBuilderTest.kt`.
final class RunLapsTests: XCTestCase {

    private func mark(_ index: Int, _ atSeconds: Double, _ metres: Double) -> LapMark {
        LapMark(index: index, atSeconds: atSeconds, distanceMetres: metres)
    }

    // MARK: - splits()

    func testNoMarksProducesNoSplits() {
        XCTAssertEqual(
            RunLaps.splits(marks: [], totalDistanceMetres: 5000, totalDurationSeconds: 1500),
            [],
            "An unmarked run carries no `laps` key at all — an empty list here is what " +
                "keeps `syncRun` from writing one"
        )
    }

    func testSplitsArePerLapDeltasNotCumulative() {
        let laps = RunLaps.splits(
            marks: [mark(1, 300, 1000), mark(2, 640, 2000), mark(3, 960, 3000)],
            totalDistanceMetres: 3000,
            totalDurationSeconds: 960
        )
        XCTAssertEqual(laps.count, 3, "The stop coincides with the last mark — no trailing partial")
        XCTAssertEqual(laps.map(\.index), [1, 2, 3])
        XCTAssertEqual(laps.map(\.durationSeconds), [300, 340, 320])
        XCTAssertEqual(laps.map(\.distanceMetres), [1000, 1000, 1000])
    }

    func testStartOffsetIsCumulativeBeforeTheLap() {
        let laps = RunLaps.splits(
            marks: [mark(1, 300, 1000), mark(2, 640, 2000)],
            totalDistanceMetres: 2000,
            totalDurationSeconds: 640
        )
        XCTAssertEqual(
            laps.map(\.startOffsetSeconds), [0, 300],
            "`start_offset_s` is the run time at which the lap STARTED. Wear OS shipped " +
                "the cumulative-AFTER figure here once and the cross-platform fixture " +
                "caught it — the first lap must be 0"
        )
    }

    func testTrailingPartialIsEmittedAfterTheLastMark() {
        let laps = RunLaps.splits(
            marks: [mark(1, 300, 1000)],
            totalDistanceMetres: 1450,
            totalDurationSeconds: 440
        )
        XCTAssertEqual(laps.count, 2)
        XCTAssertEqual(laps[1].index, 2, "The partial takes the next index, 1-based like the marks")
        XCTAssertEqual(laps[1].startOffsetSeconds, 300)
        XCTAssertEqual(laps[1].durationSeconds, 140)
        XCTAssertEqual(laps[1].distanceMetres, 450, accuracy: 0.0001)
    }

    func testLapThenImmediateStopProducesNoPhantomPartial() {
        let laps = RunLaps.splits(
            marks: [mark(1, 300, 1000)],
            totalDistanceMetres: 1000.4,
            totalDurationSeconds: 300
        )
        XCTAssertEqual(
            laps.count, 1,
            "A trailing partial under 1 s and 1 m is the runner's thumb, not a lap"
        )
    }

    func testDegenerateMarksNeverProduceNegativeSplits() {
        // Distance cannot fall, but the guard is what keeps a floating-point
        // wobble or a checkpoint written mid-update out of the row: a negative
        // `distance_m` would reach Postgres and every reader of it.
        let laps = RunLaps.splits(
            marks: [mark(1, 300, 1000), mark(2, 290, 990)],
            totalDistanceMetres: 1000,
            totalDurationSeconds: 300
        )
        XCTAssertEqual(laps[1].durationSeconds, 0)
        XCTAssertEqual(laps[1].distanceMetres, 0)
    }

    // MARK: - envelopeValue()

    func testEnvelopeValueUsesTheRegisteredKeyNames() {
        let value = RunLaps.envelopeValue(
            RunLaps.splits(
                marks: [mark(1, 300, 1000)],
                totalDistanceMetres: 1000,
                totalDurationSeconds: 300
            )
        )
        XCTAssertEqual(value.count, 1)
        XCTAssertEqual(
            Set(value[0].keys), ["index", "start_offset_s", "distance_m", "duration_s"],
            "These four names are the registry's (docs/backend/metadata.md § laps) and are " +
                "what the phone bridge forwards verbatim onto the row — a rename here is a " +
                "column the run-detail views cannot read"
        )
        XCTAssertEqual(value[0]["index"] as? Int, 1)
        XCTAssertEqual(value[0]["start_offset_s"] as? Int, 0)
        XCTAssertEqual(value[0]["distance_m"] as? Double, 1000)
        XCTAssertEqual(value[0]["duration_s"] as? Int, 300)
    }

    func testEnvelopeValueIsAPropertyList() {
        let value = RunLaps.envelopeValue(
            RunLaps.splits(
                marks: [mark(1, 300, 1000), mark(2, 610, 2000)],
                totalDistanceMetres: 2000,
                totalDurationSeconds: 610
            )
        )
        XCTAssertTrue(
            PropertyListSerialization.propertyList(value, isValidFor: .binary),
            "WCSession refuses a transfer whose metadata is not a property list, and it " +
                "refuses the WHOLE transfer — a non-plist lap value costs the run, not its laps"
        )
    }

    // MARK: - Crash recovery

    func testLapMarksSurviveTheCheckpointRoundTrip() {
        let id = "laps-\(UUID().uuidString.lowercased())"
        let store = CheckpointStore(runId: id)
        defer { store.clear() }
        store.write(checkpoint: RunCheckpoint(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMetres: 2400,
            activeDurationSeconds: 700,
            pausedIntervalSeconds: 0,
            trackPointCount: 12,
            cacheFileURL: store.trackFileURL,
            averageBPM: nil,
            hrCoverage: nil,
            steps: nil,
            laps: [mark(1, 300, 1000), mark(2, 610, 2000)]
        ))

        XCTAssertEqual(
            CheckpointStore.peekCheckpoint()?.laps, [mark(1, 300, 1000), mark(2, 610, 2000)],
            "Marks are held cumulative in the checkpoint: the split a mark opens is not " +
                "known until the next mark or the stop, neither of which an in-flight run has"
        )
    }

    func testRecoveredRunKeepsItsLapsAndClosesTheTrailingSplit() {
        let id = "laps-recover-\(UUID().uuidString.lowercased())"
        let store = CheckpointStore(runId: id)
        store.appendTrackPoints([
            TrackPointRecord(lat: 51.45, lng: -0.19, ele: nil, ts: "2026-04-15T07:30:01Z"),
        ])
        store.closeAppendHandle()
        defer { store.clear() }
        store.write(checkpoint: RunCheckpoint(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMetres: 2400,
            activeDurationSeconds: 700,
            pausedIntervalSeconds: 0,
            trackPointCount: 1,
            cacheFileURL: store.trackFileURL,
            averageBPM: nil,
            hrCoverage: nil,
            steps: nil,
            laps: [mark(1, 300, 1000), mark(2, 610, 2000)]
        ))

        let wm = WorkoutManager()
        let recovered = wm.recoverRun()
        XCTAssertEqual(
            recovered?.laps.map(\.index), [1, 2, 3],
            "A crash-recovered run must land the laps the runner marked — losing them " +
                "uploads a run whose splits exist nowhere (the Wear OS lesson of #389)"
        )
        XCTAssertEqual(recovered?.laps.last?.durationSeconds, 90)
        XCTAssertEqual(recovered?.laps.last?.distanceMetres ?? -1, 400, accuracy: 0.0001)
        XCTAssertEqual(wm.lapMarks.count, 2)
    }

    func testCheckpointFromABuildWithoutLapsDecodesAsNoMarks() throws {
        let json = """
        {"version":1,"id":"old","startedAt":"2026-04-15T07:30:00Z","distanceMetres":1000,
         "activeDurationSeconds":300,"pausedIntervalSeconds":0,"trackPointCount":4,
         "cacheFileURL":"file:///tmp/old.ndjson"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cp = try decoder.decode(RunCheckpoint.self, from: Data(json.utf8))
        XCTAssertNil(cp.laps, "An upgrade mid-run must recover, not throw on the older shape")
    }
}
