import XCTest
@testable import WatchApp

/// Live race mode's pure half: the Arm / Go / End state machine, the
/// fail-closed decode of the phone's push, the 10 s ping cadence, the
/// once-only finisher report and the two on-disk slots behind them.
///
/// Everything a spectator sees of an Apple Watch runner is produced here, so
/// a divergence from Wear OS's `RunViewModel.maybePushRacePing` / the phone's
/// `RaceController` shows up on one live link as two different runners. The
/// transport itself (`WCSession.sendMessage` / `transferUserInfo`) is not
/// driven — it cannot be constructed in the test host, which is why the
/// decisions are in a value type and the sending is a seam.
final class LiveRaceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "LiveRaceTests"

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

    private func payload(
        eventId: Any = "event-1",
        instanceStart: Any = "2026-05-22T18:00:00+00:00",
        status: Any = "armed",
        title: Any? = "Thames Half"
    ) -> [String: Any] {
        var out: [String: Any] = [
            "race_event_id": eventId,
            "race_instance_start": instanceStart,
            "race_status": status
        ]
        if let title { out["race_event_title"] = title }
        return out
    }

    private func race(_ status: RaceStatus, eventId: String = "event-1") -> LiveRace {
        LiveRace(
            eventId: eventId,
            instanceStart: "2026-05-22T18:00:00+00:00",
            status: status,
            eventTitle: "Thames Half"
        )
    }

    private func sample(
        uptime: TimeInterval,
        lat: Double = 51.5,
        lng: Double = -0.12,
        distance: Double = 1234.5,
        elapsed: Int = 600,
        bpm: Int? = 152
    ) -> RacePingSample {
        RacePingSample(
            latitude: lat,
            longitude: lng,
            distanceMetres: distance,
            elapsedSeconds: elapsed,
            bpm: bpm,
            uptime: uptime
        )
    }

    // MARK: - Decode

    func testDecodesAnArmedPush() {
        let decoded = LiveRace.decode(payload())
        XCTAssertEqual(decoded?.eventId, "event-1")
        XCTAssertEqual(decoded?.instanceStart, "2026-05-22T18:00:00+00:00")
        XCTAssertEqual(decoded?.status, .armed)
        XCTAssertEqual(decoded?.eventTitle, "Thames Half")
        XCTAssertTrue(decoded?.isArmed == true)
        XCTAssertFalse(decoded?.isRunning == true)
    }

    func testDecodesEachStatusWordTheServerCanHold() {
        for word in ["armed", "running", "finished", "cancelled"] {
            XCTAssertEqual(
                LiveRace.decode(payload(status: word))?.status,
                RaceStatus(rawValue: word),
                "`\(word)` is a race_sessions.status value and must decode"
            )
        }
    }

    func testNilOnAnUnknownStatusWord() {
        // Fail closed: a status this build does not know is a push it cannot
        // act on, and guessing would either clear a live race or ping an
        // ended one.
        XCTAssertNil(LiveRace.decode(payload(status: "paused")))
        XCTAssertNil(LiveRace.decode(payload(status: "ARMED")))
        XCTAssertNil(LiveRace.decode(payload(status: 1)))
    }

    func testNilOnAMissingOrEmptyEventId() {
        var p = payload()
        p.removeValue(forKey: "race_event_id")
        XCTAssertNil(LiveRace.decode(p))
        XCTAssertNil(LiveRace.decode(payload(eventId: "")))
        XCTAssertNil(LiveRace.decode(payload(eventId: 42)))
    }

    func testNilOnAMissingOrEmptyInstanceStart() {
        var p = payload()
        p.removeValue(forKey: "race_instance_start")
        XCTAssertNil(LiveRace.decode(p))
        XCTAssertNil(LiveRace.decode(payload(instanceStart: "")))
        XCTAssertNil(LiveRace.decode(payload(instanceStart: 0)))
    }

    func testAnAbsentOrBlankTitleDecodesToNilRatherThanBlank() {
        XCTAssertNil(LiveRace.decode(payload(title: nil))?.eventTitle)
        XCTAssertNil(LiveRace.decode(payload(title: "   "))?.eventTitle)
        XCTAssertEqual(LiveRace.decode(payload(title: "  Thames Half "))?.eventTitle,
                       "Thames Half")
    }

    func testARoutePushCarriesNoRace() {
        // The two envelopes ride the same `receive(_:)`, and every key there
        // is applied independently — a route arriving must not read as a
        // race ending.
        let routeOnly: [String: Any] = [
            "route_id": "route-1",
            "route_name": "Riverside loop",
            "route_distance_m": 5120.0,
            "route_lat": [51.5, 51.51],
            "route_lng": [-0.12, -0.11]
        ]
        XCTAssertNil(LiveRace.decode(routeOnly))
    }

    // MARK: - Arm / Go / End

    func testStartsWithNoRace() {
        let state = LiveRaceState()
        XCTAssertNil(state.race)
        XCTAssertNil(state.lastPingUptime)
    }

    func testRestoringAnEndedRaceFromDiskYieldsNoRace() {
        // A slot written before the End push landed, or one the End push
        // could not be delivered for. Neither may resurrect a race.
        XCTAssertNil(LiveRaceState(race: race(.finished)).race)
        XCTAssertNil(LiveRaceState(race: race(.cancelled)).race)
        XCTAssertEqual(LiveRaceState(race: race(.armed)).race, race(.armed))
    }

    func testArmAdoptsTheRaceAndReportsTheChange() {
        var state = LiveRaceState()
        XCTAssertTrue(state.apply(race(.armed)))
        XCTAssertEqual(state.race, race(.armed))
    }

    func testRepeatingTheSamePushReportsNoChange() {
        var state = LiveRaceState()
        state.apply(race(.armed))
        XCTAssertFalse(state.apply(race(.armed)))
    }

    func testGoMovesArmedToRunning() {
        var state = LiveRaceState()
        state.apply(race(.armed))
        XCTAssertTrue(state.apply(race(.running)))
        XCTAssertTrue(state.race?.isRunning == true)
    }

    func testEndClearsTheRace() {
        for ending in [RaceStatus.finished, .cancelled] {
            var state = LiveRaceState()
            state.apply(race(.running))
            XCTAssertTrue(state.apply(race(ending)))
            XCTAssertNil(state.race, "\(ending) must leave nothing on the wrist")
        }
    }

    func testApplyingNilClearsAndIsIdempotent() {
        var state = LiveRaceState()
        state.apply(race(.armed))
        XCTAssertTrue(state.apply(nil))
        XCTAssertNil(state.race)
        XCTAssertFalse(state.apply(nil))
    }

    func testANewInstanceOfTheSameEventIsANewRace() {
        // `(event_id, instance_start)` is the race's identity — instance 2 of
        // a recurring event is a different race from instance 1, and the
        // phone's `_setActive` learned this the hard way.
        var state = LiveRaceState()
        state.apply(race(.armed))
        let nextInstance = LiveRace(
            eventId: "event-1",
            instanceStart: "2026-05-29T18:00:00+00:00",
            status: .armed,
            eventTitle: "Thames Half"
        )
        XCTAssertTrue(state.apply(nextInstance))
        XCTAssertEqual(state.race?.instanceStart, "2026-05-29T18:00:00+00:00")
    }

    // MARK: - Ping cadence

    func testNoPingWithoutARace() {
        var state = LiveRaceState()
        XCTAssertNil(state.ping(sample(uptime: 100)))
    }

    func testNoPingBeforeGo() {
        var state = LiveRaceState()
        state.apply(race(.armed))
        XCTAssertNil(state.ping(sample(uptime: 100)))
        XCTAssertNil(state.lastPingUptime)
    }

    func testTheFirstFixAfterGoPings() {
        var state = LiveRaceState()
        state.apply(race(.running))
        let payload = state.ping(sample(uptime: 100))
        XCTAssertEqual(payload?["race_ping_event_id"] as? String, "event-1")
        XCTAssertEqual(payload?["race_ping_instance_start"] as? String,
                       "2026-05-22T18:00:00+00:00")
        XCTAssertEqual(payload?["race_ping_lat"] as? Double, 51.5)
        XCTAssertEqual(payload?["race_ping_lng"] as? Double, -0.12)
        XCTAssertEqual(payload?["race_ping_distance_m"] as? Double, 1234.5)
        XCTAssertEqual(payload?["race_ping_elapsed_s"] as? Int, 600)
        XCTAssertEqual(payload?["race_ping_bpm"] as? Int, 152)
    }

    func testTheCadenceIsTenSecondsAndTheBoundaryIsInclusive() {
        var state = LiveRaceState()
        state.apply(race(.running))
        XCTAssertEqual(LiveRaceState.pingIntervalSeconds, 10,
                       "Wear OS and the phone both debounce to 10 s")
        XCTAssertNotNil(state.ping(sample(uptime: 100)))
        XCTAssertNil(state.ping(sample(uptime: 109.9)))
        XCTAssertNotNil(state.ping(sample(uptime: 110)))
    }

    func testGoResetsTheCadenceSoTheRaceStartsOnTheNextFix() {
        // An armed race the runner is warming up on has no pings, so the
        // clock the gate reads must not be one a warm-up set. A GO landing
        // between two fixes has to ping on the very next one.
        var state = LiveRaceState()
        state.apply(race(.running))
        XCTAssertNotNil(state.ping(sample(uptime: 100)))
        state.apply(race(.armed))
        state.apply(race(.running))
        XCTAssertNotNil(state.ping(sample(uptime: 101)))
    }

    func testAnUnusableFixNeitherPingsNorConsumesTheSlot() {
        var state = LiveRaceState()
        state.apply(race(.running))
        XCTAssertNil(state.ping(sample(uptime: 100, lat: .nan)))
        XCTAssertNil(state.ping(sample(uptime: 100, lng: .infinity)))
        XCTAssertNil(state.ping(sample(uptime: 100, distance: -1)))
        XCTAssertNil(state.lastPingUptime)
        XCTAssertNotNil(state.ping(sample(uptime: 100)))
    }

    func testAnUnmeasuredHeartRateOmitsTheKeyRatherThanSendingZero() {
        var state = LiveRaceState()
        state.apply(race(.running))
        XCTAssertNil(state.ping(sample(uptime: 100, bpm: nil))?["race_ping_bpm"])
        XCTAssertNil(state.ping(sample(uptime: 200, bpm: 0))?["race_ping_bpm"])
    }

    func testAClockThatWentBackwardsStillPings() {
        // `systemUptime` restarts at zero across a reboot. Reading that as
        // "the last ping was in the future" would stall the spectator map
        // for the length of the previous uptime.
        var state = LiveRaceState()
        state.apply(race(.running))
        XCTAssertNotNil(state.ping(sample(uptime: 40_000)))
        XCTAssertNotNil(state.ping(sample(uptime: 3)))
    }

    // MARK: - Finisher report

    func testFinishingARunningRaceReportsOnceAndClearsIt() {
        var state = LiveRaceState()
        state.apply(race(.running))
        let finish = RaceFinish(runId: "run-9", durationSeconds: 5_412, distanceMetres: 21_097.5)
        let payload = state.finish(finish)
        XCTAssertEqual(payload?["race_result_event_id"] as? String, "event-1")
        XCTAssertEqual(payload?["race_result_instance_start"] as? String,
                       "2026-05-22T18:00:00+00:00")
        XCTAssertEqual(payload?["race_result_run_id"] as? String, "run-9")
        XCTAssertEqual(payload?["race_result_duration_s"] as? Int, 5_412)
        XCTAssertEqual(payload?["race_result_distance_m"] as? Double, 21_097.5)
        XCTAssertNil(state.race)
        XCTAssertNil(state.finish(finish), "a second stop must not re-submit the time")
    }

    func testFinishingAnArmedRaceReportsNothingAndKeepsIt() {
        // The runner recorded something before the organiser said GO. That
        // is not a finisher time, and the race they are still waiting on
        // must survive it.
        var state = LiveRaceState()
        state.apply(race(.armed))
        XCTAssertNil(state.finish(
            RaceFinish(runId: "run-9", durationSeconds: 600, distanceMetres: 1_000)))
        XCTAssertEqual(state.race, race(.armed))
    }

    func testFinishingWithNoRaceReportsNothing() {
        var state = LiveRaceState()
        XCTAssertNil(state.finish(
            RaceFinish(runId: "run-9", durationSeconds: 600, distanceMetres: 1_000)))
    }

    func testPingsStopOnceTheRunnerHasFinished() {
        var state = LiveRaceState()
        state.apply(race(.running))
        _ = state.finish(RaceFinish(runId: "run-9", durationSeconds: 600, distanceMetres: 1_000))
        XCTAssertNil(state.ping(sample(uptime: 1_000)))
    }

    // MARK: - Banner

    func testBannerPhaseFollowsTheRaceAndShowsNothingOnceItEnds() {
        XCTAssertNil(RaceBanner.phase(for: nil))
        XCTAssertEqual(RaceBanner.phase(for: race(.armed)), .armed)
        XCTAssertEqual(RaceBanner.phase(for: race(.running)), .live)
        XCTAssertNil(RaceBanner.phase(for: race(.finished)))
        XCTAssertNil(RaceBanner.phase(for: race(.cancelled)))
    }

    func testBannerTitleFallsBackWhenThePushCarriedNone() {
        XCTAssertEqual(RaceBanner.title(for: race(.armed)), "Thames Half")
        XCTAssertNil(RaceBanner.title(for: nil))
        XCTAssertNil(RaceBanner.title(for: LiveRace(
            eventId: "event-1", instanceStart: "i", status: .armed, eventTitle: nil)))
        XCTAssertNil(RaceBanner.title(for: LiveRace(
            eventId: "event-1", instanceStart: "i", status: .armed, eventTitle: "  ")))
    }

    // MARK: - Stores

    func testRaceStoreRoundTripsAndClears() {
        XCTAssertNil(LiveRaceStore.load(defaults: defaults))
        LiveRaceStore.save(race(.running), defaults: defaults)
        XCTAssertEqual(LiveRaceStore.load(defaults: defaults), race(.running))
        LiveRaceStore.clear(defaults: defaults)
        XCTAssertNil(LiveRaceStore.load(defaults: defaults))
    }

    func testRaceStoreLoadIsNilOnGarbageRatherThanCrashing() {
        defaults.set(Data("not json".utf8), forKey: "live_race_v1")
        XCTAssertNil(LiveRaceStore.load(defaults: defaults))
    }

    func testPendingResultsDrainOnceAndInOrder() {
        let first = RaceEnvelope.result(
            race: race(.running, eventId: "event-1"),
            finish: RaceFinish(runId: "run-1", durationSeconds: 1, distanceMetres: 1))
        let second = RaceEnvelope.result(
            race: race(.running, eventId: "event-2"),
            finish: RaceFinish(runId: "run-2", durationSeconds: 2, distanceMetres: 2))
        PendingRaceResultStore.append(first, defaults: defaults)
        PendingRaceResultStore.append(second, defaults: defaults)

        let drained = PendingRaceResultStore.drain(defaults: defaults)
        XCTAssertEqual(drained.count, 2)
        XCTAssertEqual(drained.first?["race_result_run_id"] as? String, "run-1")
        XCTAssertEqual(drained.last?["race_result_run_id"] as? String, "run-2")
        XCTAssertTrue(PendingRaceResultStore.drain(defaults: defaults).isEmpty)
    }

    func testRequeueingTheSameRaceReplacesItsEarlierTime() {
        let r = race(.running)
        PendingRaceResultStore.append(
            RaceEnvelope.result(race: r, finish: RaceFinish(
                runId: "run-1", durationSeconds: 1, distanceMetres: 1)),
            defaults: defaults)
        PendingRaceResultStore.append(
            RaceEnvelope.result(race: r, finish: RaceFinish(
                runId: "run-2", durationSeconds: 2, distanceMetres: 2)),
            defaults: defaults)

        let drained = PendingRaceResultStore.drain(defaults: defaults)
        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained.first?["race_result_run_id"] as? String, "run-2")
    }

    func testPendingResultsAreCappedAndTheOldestGoFirst() {
        for i in 0..<(PendingRaceResultStore.maxEntries + 3) {
            PendingRaceResultStore.append(
                RaceEnvelope.result(
                    race: race(.running, eventId: "event-\(i)"),
                    finish: RaceFinish(runId: "run-\(i)", durationSeconds: i, distanceMetres: 1)),
                defaults: defaults)
        }
        let drained = PendingRaceResultStore.drain(defaults: defaults)
        XCTAssertEqual(drained.count, PendingRaceResultStore.maxEntries)
        XCTAssertEqual(drained.first?["race_result_run_id"] as? String, "run-3")
        XCTAssertEqual(drained.last?["race_result_run_id"] as? String,
                       "run-\(PendingRaceResultStore.maxEntries + 2)")
    }

    // MARK: - Recorder seam

    func testTheDefaultRelayIsANoOp() {
        // `WorkoutManager` holds one of these from the moment it is
        // constructed, and a run recorded before `ContentView` wires the
        // transport must not reach for one.
        let relay = LiveRaceRelay()
        relay.ping(sample(uptime: 1))
        relay.finish(RaceFinish(runId: "run-1", durationSeconds: 1, distanceMetres: 1))
    }
}
