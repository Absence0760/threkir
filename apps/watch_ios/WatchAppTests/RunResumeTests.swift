import XCTest
import CoreLocation
@testable import WatchApp

/// Continuing a run after the app was terminated in the middle of it
/// (decisions § 1793).
///
/// The relaunch itself — watchOS calling `handleActiveWorkoutRecovery()` and
/// HealthKit handing back a live `HKWorkoutSession` — needs a wrist: no
/// session can be constructed in the test host. Everything that decides what
/// the resumed run says is reachable without one, and is pinned here: the
/// clock arithmetic, the heart-rate carry-over, the handoff ordering, the
/// checkpoint's new fields, and `restoreRun`, which is the whole of the
/// resume short of starting the frameworks again.
final class RunResumeTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() {
        CheckpointStore.clearStatic()
        super.tearDown()
    }

    private func checkpoint(
        id: String = "resume-test",
        active: TimeInterval = 8 * 3600,
        paused: TimeInterval = 600,
        pausedAt: Date? = nil,
        averageBPM: Double? = 141,
        hrCoverage: Double? = 0.9,
        hrMeanUngraded: Double? = nil,
        hrCoveredSeconds: Double? = nil,
        steps: Int? = nil,
        laps: [LapMark]? = nil,
        distance: Double = 61_000,
        trackFileURL: URL? = nil
    ) -> RunCheckpoint {
        RunCheckpoint(
            id: id,
            startedAt: start,
            distanceMetres: distance,
            activeDurationSeconds: active,
            pausedIntervalSeconds: paused,
            trackPointCount: 0,
            cacheFileURL: trackFileURL ?? URL(fileURLWithPath: NSTemporaryDirectory()),
            averageBPM: averageBPM,
            hrCoverage: hrCoverage,
            steps: steps,
            laps: laps,
            activityType: RunActivityType.hike.rawValue,
            pausedAt: pausedAt,
            hrMeanUngraded: hrMeanUngraded,
            hrCoveredSeconds: hrCoveredSeconds
        )
    }

    /// The moment a recording checkpoint describes.
    private func checkpointedAt(_ cp: RunCheckpoint) -> Date {
        start.addingTimeInterval(cp.activeDurationSeconds + cp.pausedIntervalSeconds)
    }

    // MARK: - The clock

    func testASurvivingSessionCreditsTheGapAsRunningTime() {
        let cp = checkpoint()
        let now = checkpointedAt(cp).addingTimeInterval(300)
        let plan = RunResumePlan.make(checkpoint: cp, now: now, workoutSessionSurvived: true)
        XCTAssertEqual(plan.elapsedSeconds, 8 * 3600 + 300, accuracy: 0.001,
                       "watchOS kept the workout running, so the runner was moving")
        XCTAssertEqual(plan.totalPausedInterval, 600, accuracy: 0.001)
        XCTAssertEqual(plan.gapSeconds, 300, accuracy: 0.001)
        XCTAssertFalse(plan.resumesPaused)
        // The ticker's own formula must land on the same clock.
        XCTAssertEqual(
            now.timeIntervalSince(start) - plan.totalPausedInterval, plan.elapsedSeconds, accuracy: 0.001
        )
    }

    func testWithNoSurvivingSessionTheGapIsCarriedAsPaused() {
        let cp = checkpoint()
        let now = checkpointedAt(cp).addingTimeInterval(2 * 3600)
        let plan = RunResumePlan.make(checkpoint: cp, now: now, workoutSessionSurvived: false)
        XCTAssertEqual(plan.elapsedSeconds, 8 * 3600, accuracy: 0.001,
                       "nothing shows the runner was running across the gap, so it is not timed as running")
        XCTAssertEqual(plan.totalPausedInterval, 600 + 2 * 3600, accuracy: 0.001)
        XCTAssertEqual(
            now.timeIntervalSince(start) - plan.totalPausedInterval, plan.elapsedSeconds, accuracy: 0.001
        )
    }

    func testAPausedCheckpointResumesPausedFromItsOwnPause() {
        let pausedAt = start.addingTimeInterval(8 * 3600 + 600)
        let cp = checkpoint(pausedAt: pausedAt)
        let plan = RunResumePlan.make(
            checkpoint: cp, now: pausedAt.addingTimeInterval(1200), workoutSessionSurvived: true
        )
        XCTAssertTrue(plan.resumesPaused)
        XCTAssertEqual(plan.pausedAt, pausedAt)
        XCTAssertEqual(plan.elapsedSeconds, 8 * 3600, accuracy: 0.001,
                       "a paused run's clock stays where the pause froze it, survived session or not")
        XCTAssertEqual(plan.totalPausedInterval, 600, accuracy: 0.001)
        XCTAssertEqual(plan.gapSeconds, 1200, accuracy: 0.001)
    }

    func testClockSkewNeverRunsTheActiveClockBackwards() {
        let cp = checkpoint()
        let now = checkpointedAt(cp).addingTimeInterval(-90)
        for survived in [true, false] {
            let plan = RunResumePlan.make(checkpoint: cp, now: now, workoutSessionSurvived: survived)
            XCTAssertEqual(plan.elapsedSeconds, 8 * 3600, accuracy: 0.001)
            XCTAssertEqual(plan.gapSeconds, 0)
            XCTAssertEqual(
                now.timeIntervalSince(start) - plan.totalPausedInterval, plan.elapsedSeconds, accuracy: 0.001,
                "the ticker must resume on the checkpoint's clock, not 90 s behind it"
            )
        }
    }

    func testOnlyARecentCheckpointCanBeContinued() {
        let cp = checkpoint()
        let at = checkpointedAt(cp)
        XCTAssertTrue(RunResumePlan.canContinue(cp, now: at.addingTimeInterval(60)))
        XCTAssertTrue(RunResumePlan.canContinue(cp, now: at.addingTimeInterval(RunResumePlan.maxContinueGapSeconds)))
        XCTAssertFalse(RunResumePlan.canContinue(cp, now: at.addingTimeInterval(RunResumePlan.maxContinueGapSeconds + 1)),
                       "a checkpoint older than a night is a run that ended")
        XCTAssertTrue(RunResumePlan.canContinue(cp, now: at.addingTimeInterval(-600)),
                      "a wrist clock corrected backwards is no reason to lose the run")
        XCTAssertFalse(RunResumePlan.canContinue(checkpoint(id: ""), now: at),
                       "a checkpoint with no id has no track file to continue into")
    }

    func testAPausedCheckpointIsAgedFromItsPause() {
        let pausedAt = start.addingTimeInterval(3600)
        let cp = checkpoint(active: 3000, paused: 600, pausedAt: pausedAt)
        XCTAssertEqual(RunResumePlan.checkpointedAt(cp), pausedAt)
        XCTAssertFalse(RunResumePlan.canContinue(
            cp, now: pausedAt.addingTimeInterval(RunResumePlan.maxContinueGapSeconds + 1)
        ))
    }

    // MARK: - Heart rate

    func testThePriorIsTheRawMeasurementWhenTheCheckpointCarriesIt() {
        let cp = checkpoint(averageBPM: nil, hrCoverage: 0.4, hrMeanUngraded: 150, hrCoveredSeconds: 11_520)
        let prior = RunResumePlan.heartRatePrior(cp, resumingAt: 29_000)
        XCTAssertEqual(prior.mean, 150,
                       "a mean graded away at 40 % coverage is still the samples the run took")
        XCTAssertEqual(prior.coveredSeconds, 11_520, accuracy: 0.001)
        XCTAssertEqual(prior.atActiveSeconds, 29_000, accuracy: 0.001)
    }

    func testAnOlderCheckpointFallsBackToTheGradedPair() {
        let cp = checkpoint(averageBPM: 141, hrCoverage: 0.9)
        let prior = RunResumePlan.heartRatePrior(cp, resumingAt: cp.activeDurationSeconds)
        XCTAssertEqual(prior.mean, 141)
        XCTAssertEqual(prior.coveredSeconds, 0.9 * 8 * 3600, accuracy: 0.001)
    }

    func testAnUnmeasuredCheckpointCarriesNothing() {
        let cp = checkpoint(averageBPM: nil, hrCoverage: nil)
        let prior = RunResumePlan.heartRatePrior(cp, resumingAt: 1)
        XCTAssertNil(prior.mean)
        XCTAssertEqual(prior.coveredSeconds, 0)
    }

    func testTheBlendWeightsEachMeanByItsCoverage() {
        let mean = HeartRateCoverage.blendedMean(
            priorMean: 140, priorWeightSeconds: 8 * 3600, currentMean: 170, currentWeightSeconds: 3600
        )
        XCTAssertEqual(mean ?? -1, (140.0 * 8 + 170) / 9, accuracy: 1e-9,
                       "an hour after the relaunch must not outvote eight hours before it")
    }

    func testTheBlendFallsBackToWhicheverSideExists() {
        XCTAssertEqual(HeartRateCoverage.blendedMean(
            priorMean: 140, priorWeightSeconds: 100, currentMean: nil, currentWeightSeconds: 0
        ), 140)
        XCTAssertEqual(HeartRateCoverage.blendedMean(
            priorMean: nil, priorWeightSeconds: 100, currentMean: 150, currentWeightSeconds: 10
        ), 150)
        XCTAssertNil(HeartRateCoverage.blendedMean(
            priorMean: nil, priorWeightSeconds: 0, currentMean: nil, currentWeightSeconds: 0
        ))
        XCTAssertEqual(HeartRateCoverage.blendedMean(
            priorMean: 140, priorWeightSeconds: 0, currentMean: 150, currentWeightSeconds: 0
        ), 150, "with no weight on either side the surviving builder's whole-workout mean wins")
        XCTAssertEqual(HeartRateCoverage.blendedMean(
            priorMean: 140, priorWeightSeconds: .nan, currentMean: 150, currentWeightSeconds: 60
        ), 150)
    }

    func testRestoredCoverageCreditsNothingForTheTermination() {
        var acc = HeartRateCoverageAccumulator()
        acc.restore(coveredSeconds: 25_000, atActiveSeconds: 28_800)
        XCTAssertEqual(acc.coveredSeconds, 25_000)

        // No sample since the relaunch: nothing is credited, however far the
        // clock has moved.
        acc.advance(activeElapsedSeconds: 28_801, nowEpoch: 1_000)
        XCTAssertEqual(acc.coveredSeconds, 25_000)

        // A fresh sample credits the one-second step, not the 28 800 s run.
        acc.noteSample(atEpoch: 1_001)
        acc.advance(activeElapsedSeconds: 28_802, nowEpoch: 1_002)
        XCTAssertEqual(acc.coveredSeconds ?? -1, 25_001, accuracy: 1e-9)
    }

    func testAContinuedRunIsGradedAcrossBothHalves() {
        // 8 h at 140 bpm fully covered before the crash; the resumed session
        // has delivered nothing yet. The claim still carries the run's mean.
        let claim = HeartRateCoverage.claim(
            mean: HeartRateCoverage.blendedMean(
                priorMean: 140, priorWeightSeconds: 28_800, currentMean: nil, currentWeightSeconds: 0
            ),
            coveredSeconds: 28_800,
            activeElapsedSeconds: 28_860
        )
        XCTAssertEqual(claim.averageBPM, 140)
        XCTAssertEqual(claim.coverage, 1.0)
    }

    // MARK: - Spoken cues

    func testAPrimedAnnouncerSpeaksOnlyTheNextSplit() {
        let announcer = RunAnnouncer()
        var spoken: [String] = []
        announcer.speak = { spoken.append($0) }
        announcer.isEnabled = { true }
        announcer.prefersMiles = { false }
        announcer.primeSplits(distanceMetres: 61_400)
        XCTAssertTrue(spoken.isEmpty, "priming is silent")
        announcer.announceSplitIfDue(distanceMetres: 61_900, paceSecondsPerKm: nil)
        XCTAssertTrue(spoken.isEmpty, "the 61st kilometre was reached before the relaunch")
        announcer.announceSplitIfDue(distanceMetres: 62_000, paceSecondsPerKm: nil)
        XCTAssertEqual(spoken.count, 1)
    }

    // MARK: - The handoff

    func testAValueDeliveredBeforeTheReceiverIsHandedOverOnRegister() {
        let handoff = PendingHandoff<String>()
        handoff.deliver("session")
        var received: [String] = []
        handoff.register { received.append($0) }
        XCTAssertEqual(received, ["session"])
    }

    func testAValueDeliveredAfterTheReceiverReachesIt() {
        let handoff = PendingHandoff<String>()
        var received: [String] = []
        handoff.register { received.append($0) }
        XCTAssertTrue(received.isEmpty)
        handoff.deliver("session")
        XCTAssertEqual(received, ["session"])
    }

    func testAValueIsHandedOverOnce() {
        let handoff = PendingHandoff<String>()
        handoff.deliver("session")
        var count = 0
        handoff.register { _ in count += 1 }
        handoff.register { _ in count += 1 }
        XCTAssertEqual(count, 1, "a second registration must not replay a session already taken")
    }

    // MARK: - The checkpoint's new fields

    func testTheNewFieldsRoundTripThroughTheStore() throws {
        let id = "resume-rt-\(UUID().uuidString.lowercased())"
        let store = CheckpointStore(runId: id)
        defer { store.clear() }
        let pausedAt = Date(timeIntervalSince1970: 1_800_030_000)
        store.write(checkpoint: checkpoint(
            id: id, pausedAt: pausedAt, hrMeanUngraded: 147.5, hrCoveredSeconds: 20_000
        ))
        let read = try XCTUnwrap(CheckpointStore.peekCheckpoint())
        XCTAssertEqual(read.pausedAt, pausedAt)
        XCTAssertEqual(read.hrMeanUngraded, 147.5)
        XCTAssertEqual(read.hrCoveredSeconds, 20_000)
    }

    func testAnOlderCheckpointDecodesWithoutThem() throws {
        let json = """
        {"id":"old","startedAt":"2026-04-15T07:30:00Z","distanceMetres":100,
         "activeDurationSeconds":60,"pausedIntervalSeconds":0,"trackPointCount":1,
         "cacheFileURL":"file:///tmp/old.ndjson"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cp = try decoder.decode(RunCheckpoint.self, from: Data(json.utf8))
        XCTAssertNil(cp.pausedAt, "an older checkpoint is a recording one, not a paused one")
        XCTAssertNil(cp.hrMeanUngraded)
        XCTAssertNil(cp.hrCoveredSeconds)
    }

    // MARK: - WorkoutManager

    private func silentAnnouncer() -> RunAnnouncer {
        let announcer = RunAnnouncer()
        announcer.speak = { _ in }
        announcer.isEnabled = { true }
        announcer.prefersMiles = { false }
        return announcer
    }

    private func seededRun(points: Int) -> (CheckpointStore, RunCheckpoint) {
        let id = "resume-wm-\(UUID().uuidString.lowercased())"
        let store = CheckpointStore(runId: id)
        store.appendTrackPoints((0..<points).map {
            TrackPointRecord(lat: 46.0 + Double($0) * 0.001, lng: 7.0, ele: 1200, ts: "2026-04-15T07:30:01Z")
        })
        store.closeAppendHandle()
        let cp = checkpoint(
            id: id,
            steps: 41_000,
            laps: [LapMark(index: 1, atSeconds: 3600, distanceMetres: 9000)],
            trackFileURL: store.trackFileURL
        )
        store.write(checkpoint: cp)
        return (store, cp)
    }

    func testRestoreCarriesTheWholeRunOver() {
        let (store, cp) = seededRun(points: 50)
        defer { store.clear() }
        let wm = WorkoutManager()
        wm.announcer = silentAnnouncer()
        let plan = RunResumePlan.make(
            checkpoint: cp, now: checkpointedAt(cp).addingTimeInterval(120), workoutSessionSurvived: true
        )
        wm.restoreRun(from: cp, plan: plan)

        XCTAssertEqual(wm.state, .recording)
        XCTAssertEqual(wm.activityType, .hike, "the activity the run was recorded as")
        XCTAssertEqual(wm.distanceMetres, 61_000, accuracy: 0.001)
        XCTAssertEqual(wm.elapsedSeconds, plan.elapsedSeconds, accuracy: 0.001)
        XCTAssertEqual(wm.trackPointCount, 50, "counted off the file the run kept writing")
        XCTAssertEqual(wm.steps, 41_000)
        XCTAssertEqual(wm.lapMarks.count, 1)
        XCTAssertFalse(wm.mapTrail.points.isEmpty, "the map shows the run before the termination")
        XCTAssertEqual(wm.mapPosition?.latitude ?? 0, 46.049, accuracy: 1e-9)
        XCTAssertEqual(wm.announcer.announcedSplits, 61,
                       "the 61 km already banked must not be announced as just reached")
    }

    func testTheFirstFixAfterTheRestoreCreditsNothingForTheGap() {
        let (store, cp) = seededRun(points: 3)
        defer { store.clear() }
        let wm = WorkoutManager()
        wm.announcer = silentAnnouncer()
        wm.restoreRun(from: cp, plan: RunResumePlan.make(
            checkpoint: cp, now: checkpointedAt(cp), workoutSessionSurvived: true
        ))
        wm.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 46.2, longitude: 7.0),
            altitude: 1200, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: 0, courseAccuracy: 5, speed: 2.8, speedAccuracy: 0.3,
            timestamp: Date()
        )])
        XCTAssertEqual(wm.distanceMetres, 61_000, accuracy: 0.001,
                       "the first fix anchors a fresh segment; 20 km of straight line is not invented")
        XCTAssertEqual(wm.trackPointCount, 4, "and is appended to the same run's track")
    }

    func testAContinuedRunStopsAsOneRun() {
        let (store, cp) = seededRun(points: 10)
        defer { store.clear() }
        let wm = WorkoutManager()
        wm.announcer = silentAnnouncer()
        wm.restoreRun(from: cp, plan: RunResumePlan.make(
            checkpoint: cp, now: checkpointedAt(cp), workoutSessionSurvived: false
        ))
        wm.stop()
        let run = wm.finishedRun
        XCTAssertEqual(run?.id, cp.id, "the same id the run started with — one row on the phone")
        XCTAssertEqual(run?.startedAt, start)
        XCTAssertEqual(run?.trackFileURL, store.trackFileURL)
        XCTAssertEqual(run?.trackPointCount, 10)
        XCTAssertEqual(run?.distanceMetres ?? -1, 61_000, accuracy: 0.001)
        XCTAssertEqual(run?.steps, 41_000)
        XCTAssertEqual(run?.laps.first?.distanceMetres ?? -1, 9000, accuracy: 0.001)
        XCTAssertEqual(run?.activityType, .hike)
        XCTAssertNil(CheckpointStore.peekCheckpoint(), "a stopped run is not offered back as unsaved")
    }

    func testAPausedCheckpointRestoresPausedAndResumesOnTheRightClock() {
        let (store, _) = seededRun(points: 2)
        defer { store.clear() }
        let pausedAt = Date().addingTimeInterval(-300)
        let cp = RunCheckpoint(
            id: CheckpointStore.peekCheckpoint()!.id,
            startedAt: pausedAt.addingTimeInterval(-3600),
            distanceMetres: 9000,
            activeDurationSeconds: 3000,
            pausedIntervalSeconds: 600,
            trackPointCount: 2,
            cacheFileURL: store.trackFileURL,
            averageBPM: nil,
            hrCoverage: nil,
            steps: nil,
            laps: nil,
            pausedAt: pausedAt
        )
        let wm = WorkoutManager()
        wm.announcer = silentAnnouncer()
        wm.restoreRun(from: cp, plan: RunResumePlan.make(checkpoint: cp, now: Date(), workoutSessionSurvived: true))
        XCTAssertEqual(wm.state, .paused)
        XCTAssertEqual(wm.elapsedSeconds, 3000, accuracy: 0.001)
        wm.resume()
        XCTAssertEqual(wm.state, .recording)
        XCTAssertNil(CheckpointStore.peekCheckpoint()?.pausedAt,
                     "resuming clears the pause from the checkpoint at once")
        wm.stop()
        XCTAssertEqual(Double(wm.finishedRun?.durationSeconds ?? -1), 3000, accuracy: 1,
                       "the five minutes paused across the termination are not timed as running")
    }

    func testPausingRecordsThePauseInTheCheckpoint() {
        let (store, cp) = seededRun(points: 2)
        defer { store.clear() }
        let wm = WorkoutManager()
        wm.announcer = silentAnnouncer()
        wm.restoreRun(from: cp, plan: RunResumePlan.make(
            checkpoint: cp, now: checkpointedAt(cp), workoutSessionSurvived: true
        ))
        wm.pause()
        XCTAssertNotNil(CheckpointStore.peekCheckpoint()?.pausedAt,
                        "a run terminated while paused must come back paused")
    }

    func testNothingIsContinuedWithoutACheckpoint() {
        CheckpointStore.clearStatic()
        let wm = WorkoutManager()
        XCTAssertFalse(wm.canContinueRecoveredRun)
        XCTAssertFalse(wm.continueRecoveredRun())
        XCTAssertEqual(wm.state, .idle)
    }

    func testAStaleCheckpointIsNotContinued() {
        let (store, cp) = seededRun(points: 1)
        defer { store.clear() }
        let wm = WorkoutManager()
        let late = checkpointedAt(cp).addingTimeInterval(RunResumePlan.maxContinueGapSeconds + 60)
        XCTAssertFalse(wm.continueRecoveredRun(now: late))
        XCTAssertEqual(wm.state, .idle, "a refused continue touches nothing")
        XCTAssertNotNil(CheckpointStore.peekCheckpoint(), "and leaves the run for Save or Discard")
    }

    func testARunningRunIsNotOfferedBackAsUnsaved() {
        let (store, _) = seededRun(points: 1)
        defer { store.clear() }
        let wm = WorkoutManager()
        wm.state = .recording
        wm.checkForPendingRecovery()
        XCTAssertEqual(wm.state, .recording)
    }
}
