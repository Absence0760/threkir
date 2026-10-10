import XCTest
import CoreLocation
@testable import WatchApp

/// The most-used loop on the wrist, end to end: a run recorded, paused,
/// resumed and stopped, its payload handed off, and then the NEXT run.
///
/// The phone shipped a bug on exactly this path — a finished state that got in
/// the way of the next start — and nothing walked it. Here the loop is
/// `.recording -> .paused -> .recording -> .finished`, then `reset()` (what
/// "Start next run" and Discard both call) back to `.idle`, which is the only
/// state `ContentView` offers Start from.
///
/// `start()` itself cannot run in the test host: it requests location
/// authorization and enables background updates, which trap outside a
/// backgroundable session. A live run is stood in two ways instead, each for
/// what it can honestly show. `restoreRun` gives a run everything `start()`
/// does short of the frameworks — an id, a `CheckpointStore`, an open track
/// file, a checkpoint — so the first run is a real one on disk. The run after
/// a `reset()` is entered with a bare `state = .recording`, as the
/// HealthKit and distance suites do, so that whatever it carries can only have
/// come through `reset()`.
final class RunLifecycleTests: XCTestCase {

    private var stores: [CheckpointStore] = []
    private var exports: [URL] = []
    private let base = Date()

    override func tearDown() {
        for store in stores { store.clear() }
        stores = []
        for url in exports { try? FileManager.default.removeItem(at: url) }
        exports = []
        CheckpointStore.clearStatic()
        super.tearDown()
    }

    private func loc(_ lat: Double, at seconds: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -0.1),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            courseAccuracy: 5,
            speed: 2.8,
            speedAccuracy: 0.3,
            timestamp: base.addingTimeInterval(seconds)
        )
    }

    /// One fix per second heading north at the Doppler speed's pace.
    private func leg(from lat: Double, at start: TimeInterval, seconds: Int) -> [CLLocation] {
        let degPerSecond = 2.8 / 111_195
        return (0...seconds).map { loc(lat + Double($0) * degPerSecond, at: start + Double($0)) }
    }

    private func feed(_ wm: WorkoutManager, _ locations: [CLLocation]) {
        wm.locationManager(CLLocationManager(), didUpdateLocations: locations)
    }

    private func silentAnnouncer() -> RunAnnouncer {
        let announcer = RunAnnouncer()
        announcer.speak = { _ in }
        announcer.isEnabled = { true }
        announcer.prefersMiles = { false }
        return announcer
    }

    /// A run in progress on `wm`, the way the wrist holds one after `start()`.
    @discardableResult
    private func beginRun(
        on wm: WorkoutManager,
        id: String = "lifecycle-\(UUID().uuidString.lowercased())",
        distance: Double = 0,
        laps: [LapMark]? = nil,
        steps: Int? = nil
    ) -> CheckpointStore {
        let store = CheckpointStore(runId: id)
        stores.append(store)
        let cp = RunCheckpoint(
            id: id,
            startedAt: Date().addingTimeInterval(-600),
            distanceMetres: distance,
            activeDurationSeconds: 600,
            pausedIntervalSeconds: 0,
            trackPointCount: 0,
            cacheFileURL: store.trackFileURL,
            averageBPM: nil,
            hrCoverage: nil,
            steps: steps,
            laps: laps
        )
        store.write(checkpoint: cp)
        wm.restoreRun(from: cp, plan: RunResumePlan.make(
            checkpoint: cp, now: Date(), workoutSessionSurvived: true
        ))
        return store
    }

    private func newManager() -> WorkoutManager {
        let wm = WorkoutManager()
        wm.announcer = silentAnnouncer()
        return wm
    }

    // MARK: - One run

    func testARunWalksRecordingPausedRecordingAndFinishedUnderOneId() {
        let wm = newManager()
        let store = beginRun(on: wm, id: "lifecycle-one-run")
        XCTAssertEqual(wm.state, .recording)

        feed(wm, leg(from: 51.5, at: 0, seconds: 20))
        let beforePause = wm.distanceMetres
        XCTAssertGreaterThan(beforePause, 0)

        wm.pause()
        XCTAssertEqual(wm.state, .paused)
        XCTAssertEqual(wm.distanceMetres, beforePause, accuracy: 0.0001)
        wm.markLap()
        XCTAssertTrue(wm.lapMarks.isEmpty, "a lap is not taken while the clock is stopped")

        wm.resume()
        XCTAssertEqual(wm.state, .recording)
        let resumeLat = 51.5 + 20 * 2.8 / 111_195
        feed(wm, leg(from: resumeLat, at: 60, seconds: 10))
        XCTAssertGreaterThan(wm.distanceMetres, beforePause, "recording carries on after a resume")
        wm.markLap()
        XCTAssertEqual(wm.lapMarks.count, 1)

        let live = wm.distanceMetres
        wm.stop()

        XCTAssertEqual(wm.state, .finished)
        let run = wm.finishedRun
        XCTAssertEqual(run?.id, "lifecycle-one-run", "one id from start to the row: one run on the phone")
        XCTAssertEqual(run?.trackFileURL, store.trackFileURL)
        XCTAssertEqual(run?.trackPointCount, 32, "both halves of the run are in one track")
        XCTAssertEqual(run?.distanceMetres ?? -1, live, accuracy: 0.0001)
        XCTAssertFalse(run?.laps.isEmpty ?? true)
        XCTAssertNil(CheckpointStore.peekCheckpoint(), "a stopped run is not offered back as unsaved")
    }

    func testStoppingFromPauseFinishesTheRun() {
        let wm = newManager()
        beginRun(on: wm, id: "lifecycle-stop-paused")
        feed(wm, leg(from: 51.5, at: 0, seconds: 10))
        let banked = wm.distanceMetres
        wm.pause()

        wm.stop()

        XCTAssertEqual(wm.state, .finished, "the paused screen's hold-to-stop ends the run")
        XCTAssertEqual(wm.finishedRun?.id, "lifecycle-stop-paused")
        XCTAssertEqual(wm.finishedRun?.distanceMetres ?? -1, banked, accuracy: 0.0001)
        XCTAssertNil(CheckpointStore.peekCheckpoint())
    }

    // MARK: - Finished, then the next run

    func testStartingTheNextRunReturnsToACleanIdle() {
        let wm = newManager()
        beginRun(
            on: wm,
            distance: 5_000,
            laps: [LapMark(index: 1, atSeconds: 300, distanceMetres: 1_000)],
            steps: 6_000
        )
        feed(wm, leg(from: 51.5, at: 0, seconds: 10))
        wm.stop()
        guard let finished = wm.finishedRun else { return XCTFail("the run must finish") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: finished.trackFileURL.path))

        wm.reset()

        XCTAssertEqual(wm.state, .idle, "idle is the only state Start is offered from")
        XCTAssertNil(wm.finishedRun)
        XCTAssertEqual(wm.distanceMetres, 0)
        XCTAssertEqual(wm.elapsedSeconds, 0)
        XCTAssertNil(wm.currentPace)
        XCTAssertEqual(wm.trackPointCount, 0)
        XCTAssertTrue(wm.lapMarks.isEmpty)
        XCTAssertNil(wm.steps)
        XCTAssertNil(wm.mapPosition)
        XCTAssertTrue(wm.mapTrail.points.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finished.trackFileURL.path),
                       "back at idle nothing can still want the finished run's NDJSON")

        wm.checkForPendingRecovery()
        XCTAssertEqual(wm.state, .idle,
                       "a run that finished normally must not come back as \"Recover unsaved run?\"")
    }

    func testTheHandedOffPayloadOutlivesTheNextRunReset() throws {
        let wm = newManager()
        let store = beginRun(on: wm, id: "lifecycle-export-\(UUID().uuidString.lowercased())")
        feed(wm, leg(from: 51.5, at: 0, seconds: 5))
        wm.stop()

        // What Sync hands WCSession: a JSON file the transfer reads for as
        // long as it is outstanding — after the runner has moved on.
        let export = try wm.writeTrackJSON()
        exports.append(export)

        wm.reset()

        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path),
                      "the transfer's file must survive Start next run")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.trackFileURL.path))
    }

    func testTheNextRunInheritsNothingFromTheFinishedOne() {
        let wm = newManager()
        let first = beginRun(
            on: wm,
            id: "lifecycle-first",
            distance: 5_000,
            laps: [LapMark(index: 1, atSeconds: 300, distanceMetres: 1_000)],
            steps: 6_000
        )
        feed(wm, leg(from: 51.5, at: 0, seconds: 10))
        wm.markLap()
        wm.stop()
        XCTAssertEqual(wm.finishedRun?.id, "lifecycle-first")
        wm.reset()

        wm.state = .recording
        feed(wm, leg(from: 51.6, at: 120, seconds: 10))
        let live = wm.distanceMetres
        wm.stop()

        XCTAssertEqual(wm.state, .finished)
        guard let second = wm.finishedRun else { return XCTFail("the second run must finish") }
        XCTAssertNotEqual(second.id, "lifecycle-first", "each run is its own row")
        XCTAssertNotEqual(second.trackFileURL, first.trackFileURL)
        XCTAssertEqual(second.trackPointCount, 11, "only the second run's fixes")
        XCTAssertEqual(second.distanceMetres, live, accuracy: 0.0001)
        XCTAssertLessThan(second.distanceMetres, 100,
                          "the first run's 5 km must not be carried into the second")
        XCTAssertTrue(second.laps.isEmpty, "the first run's laps would split the second")
        XCTAssertNil(second.steps)
    }
}
