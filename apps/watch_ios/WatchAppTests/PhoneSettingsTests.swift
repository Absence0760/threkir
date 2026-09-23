import XCTest
@testable import WatchApp

/// The three settings the phone hands this wrist beyond the unit and the cue
/// switch — `default_activity_type`, `privacy_default` and the resolved
/// `hr_zone_cutoffs` — from the envelope decode through to what each one does
/// on the recorder.
final class PhoneSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "PhoneSettingsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        clearStandard()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        clearStandard()
        CheckpointStore.clearStatic()
        super.tearDown()
    }

    private func clearStandard() {
        for key in [DefaultActivityType.storageKey, PrivacyDefault.storageKey, HeartRateZones.storageKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - wire names

    func testTheStorageKeysAreTheWireKeys() {
        // Spelled once on each rail; a rename here is a setting the phone
        // sends that the wrist files somewhere nothing reads.
        XCTAssertEqual(DefaultActivityType.storageKey, "default_activity_type")
        XCTAssertEqual(PrivacyDefault.storageKey, "privacy_default")
        XCTAssertEqual(HeartRateZones.storageKey, "hr_zone_cutoffs")
    }

    // MARK: - default_activity_type

    func testEveryPickerActivityDecodes() {
        for type in RunActivityType.allCases {
            XCTAssertEqual(PhonePreferences.defaultActivityType(in: ["default_activity_type": type.rawValue]), type)
        }
    }

    func testAnActivityThePickerCannotRecordDecodesAsNothing() {
        // `stroller` is a column value no wrist picker offers; the picker keeps
        // what it shows rather than falling back to run.
        let rogues: [Any] = ["stroller", "Run", "", "swim", 1, true]
        for rogue in rogues {
            XCTAssertNil(PhonePreferences.defaultActivityType(in: ["default_activity_type": rogue]))
        }
        XCTAssertNil(PhonePreferences.defaultActivityType(in: [:]))
    }

    func testADefaultPrimesAnUntouchedIdlePicker() {
        XCTAssertEqual(
            DefaultActivityType.primed(current: .run, default: .walk, isIdle: true, pickedOnWrist: false),
            .walk
        )
        // Primes from any value, not only from run: a second push after the
        // phone default changed again still lands.
        XCTAssertEqual(
            DefaultActivityType.primed(current: .walk, default: .cycle, isIdle: true, pickedOnWrist: false),
            .cycle
        )
    }

    func testADefaultNeverOverridesTheRunnerOrARunInProgress() {
        XCTAssertEqual(
            DefaultActivityType.primed(current: .hike, default: .walk, isIdle: true, pickedOnWrist: true),
            .hike,
            "a choice made on the wrist wins over one made on the phone"
        )
        XCTAssertEqual(
            DefaultActivityType.primed(current: .run, default: .cycle, isIdle: false, pickedOnWrist: false),
            .run,
            "a run already recording as run cannot become a ride"
        )
    }

    func testTheRecorderOpensOnTheStoredDefault() {
        DefaultActivityType.save(.hike)
        XCTAssertEqual(WorkoutManager().activityType, .hike)
    }

    func testTheRecorderOpensOnRunWithNoStoredDefault() {
        XCTAssertEqual(WorkoutManager().activityType, .run)
    }

    func testTheRecorderIsPrimedUntilTheRunnerPicks() {
        let wm = WorkoutManager()
        wm.applyDefaultActivityType(.walk)
        XCTAssertEqual(wm.activityType, .walk)
        wm.pickActivityType(.cycle)
        wm.applyDefaultActivityType(.hike)
        XCTAssertEqual(wm.activityType, .cycle)
    }

    func testTheActivityStoreRoundTripsAndRefusesGarbage() {
        DefaultActivityType.save(.cycle, in: defaults)
        XCTAssertEqual(DefaultActivityType.stored(in: defaults), .cycle)
        defaults.set("stroller", forKey: DefaultActivityType.storageKey)
        XCTAssertNil(DefaultActivityType.stored(in: defaults))
    }

    // MARK: - privacy_default

    func testTheThreePrivacyValuesDecode() {
        for value in ["public", "followers", "private"] {
            XCTAssertEqual(PhonePreferences.privacyDefault(in: ["privacy_default": value]), value)
        }
    }

    func testARoguePrivacyValueDecodesAsNothing() {
        let rogues: [Any] = ["Public", "everyone", "", "true", true, 1]
        for rogue in rogues {
            XCTAssertNil(PhonePreferences.privacyDefault(in: ["privacy_default": rogue]))
        }
    }

    func testOnlyPublicPublishes() {
        XCTAssertEqual(PrivacyDefault.isPublic("public"), true)
        XCTAssertEqual(PrivacyDefault.isPublic("followers"), false,
                       "runs.is_public is a boolean; the followers nuance is the phone's")
        XCTAssertEqual(PrivacyDefault.isPublic("private"), false)
        XCTAssertNil(PrivacyDefault.isPublic(nil), "the phone never said: omit, never guess")
    }

    func testAStoredValueTheBuildCannotReadIsNoValue() {
        defaults.set("everyone", forKey: PrivacyDefault.storageKey)
        XCTAssertNil(PrivacyDefault.stored(in: defaults))
        PrivacyDefault.save("public", in: defaults)
        XCTAssertEqual(PrivacyDefault.stored(in: defaults), "public")
    }

    func testAStoppedRunCarriesThePrivacyDefaultInForceAtStop() {
        PrivacyDefault.save("public")
        let wm = WorkoutManager()
        wm.state = .recording
        wm.stop()
        XCTAssertEqual(wm.finishedRun?.isPublic, true)
    }

    func testAStoppedRunWithNoPrivacyDefaultStampsNothing() {
        let wm = WorkoutManager()
        wm.state = .recording
        wm.stop()
        XCTAssertNil(wm.finishedRun?.isPublic)
    }

    func testTheCheckpointCarriesTheSnapshotAndAnOlderOneDecodesWithout() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let cp = RunCheckpoint(
            id: "cp", startedAt: Date(timeIntervalSince1970: 0), distanceMetres: 1,
            activeDurationSeconds: 1, pausedIntervalSeconds: 0, trackPointCount: 0,
            cacheFileURL: url, averageBPM: nil, hrCoverage: nil, steps: nil, laps: nil,
            isPublic: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let round = try decoder.decode(RunCheckpoint.self, from: encoder.encode(cp))
        XCTAssertEqual(round.isPublic, true)

        let older = try decoder.decode(RunCheckpoint.self, from: Data(#"{"id":"old"}"#.utf8))
        XCTAssertNil(older.isPublic, "a checkpoint from before the field is unstated, not private")
    }

    func testARecoveredRunKeepsTheVisibilityItWasRecordedUnder() {
        // Changed on the phone since the crash: recovery must not pick that up.
        PrivacyDefault.save("private")
        let id = "recover-privacy-\(UUID().uuidString.lowercased())"
        let store = CheckpointStore(runId: id)
        store.appendTrackPoints([TrackPointRecord(lat: 1, lng: 1, ele: nil, ts: "2026-09-23T07:30:01Z")])
        store.closeAppendHandle()
        store.write(checkpoint: RunCheckpoint(
            id: id, startedAt: Date(), distanceMetres: 100, activeDurationSeconds: 60,
            pausedIntervalSeconds: 0, trackPointCount: 1, cacheFileURL: store.trackFileURL,
            averageBPM: nil, hrCoverage: nil, steps: nil, laps: nil, isPublic: true
        ))
        defer { store.clear() }
        XCTAssertEqual(WorkoutManager().recoverRun()?.isPublic, true)
    }

    // MARK: - hr_zone_cutoffs

    func testALadderDecodes() {
        XCTAssertEqual(
            PhonePreferences.hrZoneCutoffs(in: ["hr_zone_cutoffs": [114, 133, 152, 171, 190]]),
            [114, 133, 152, 171, 190]
        )
        XCTAssertEqual(
            PhonePreferences.hrZoneCutoffs(in: ["hr_zone_cutoffs": [40, 41, 42, 43, 240]]),
            [40, 41, 42, 43, 240],
            "the range is inclusive at both ends"
        )
    }

    func testAnEmptyLadderIsAnInstructionToClear() {
        XCTAssertEqual(PhonePreferences.hrZoneCutoffs(in: ["hr_zone_cutoffs": [Int]()]), [])
    }

    func testAnythingElseIsNotALadder() {
        let rogues: [Any] = [
            [150, 140, 130, 120, 110],
            [114, 114, 152, 171, 190],
            [39, 133, 152, 171, 190],
            [114, 133, 152, 171, 241],
            [114, 133, 152, 171],
            [114, 133, 152, 171, 190, 200],
            [114.5, 133, 152, 171, 190],
            "114,133,152,171,190",
            114,
        ]
        for rogue in rogues {
            XCTAssertNil(PhonePreferences.hrZoneCutoffs(in: ["hr_zone_cutoffs": rogue]), "\(rogue)")
        }
        XCTAssertNil(PhonePreferences.hrZoneCutoffs(in: [:]), "absent is 'keep what you have'")
    }

    func testTheLadderStoreRoundTripsAndReadsEmptyWhenUnset() {
        XCTAssertEqual(HeartRateZones.stored(in: defaults), [])
        HeartRateZones.save([114, 133, 152, 171, 190], in: defaults)
        XCTAssertEqual(HeartRateZones.stored(in: defaults), [114, 133, 152, 171, 190])
        HeartRateZones.save([], in: defaults)
        XCTAssertEqual(HeartRateZones.stored(in: defaults), [])
        defaults.set([5, 4, 3, 2, 1], forKey: HeartRateZones.storageKey)
        XCTAssertEqual(HeartRateZones.stored(in: defaults), [], "a corrupt slot badges nothing")
    }

    func testAReadingFallsInTheZoneItsBoundCloses() {
        let ladder = [114, 133, 152, 171, 190]
        XCTAssertEqual(HeartRateZones.zone(bpm: 60, cutoffs: ladder), 1)
        XCTAssertEqual(HeartRateZones.zone(bpm: 114, cutoffs: ladder), 1)
        XCTAssertEqual(HeartRateZones.zone(bpm: 115, cutoffs: ladder), 2)
        XCTAssertEqual(HeartRateZones.zone(bpm: 146, cutoffs: ladder), 3)
        XCTAssertEqual(HeartRateZones.zone(bpm: 171, cutoffs: ladder), 4)
        XCTAssertEqual(HeartRateZones.zone(bpm: 172, cutoffs: ladder), 5)
        XCTAssertEqual(HeartRateZones.zone(bpm: 230, cutoffs: ladder), 5,
                       "above the top bound is still Z5, as on Wear OS")
    }

    func testNoLadderIsNoBadge() {
        XCTAssertNil(HeartRateZones.zone(bpm: 146, cutoffs: []))
        XCTAssertNil(HeartRateZones.zone(bpm: 146, cutoffs: [114, 133]))
    }

    // MARK: - independence

    func testEachSettingIsReadWithoutTheOthers() {
        // A route push carries none of them, an older phone build carries only
        // the unit and the cues. Every reader answers for its own key alone.
        let unitOnly: [String: Any] = ["preferred_unit": "mi", "audio_cues": true]
        XCTAssertNil(PhonePreferences.defaultActivityType(in: unitOnly))
        XCTAssertNil(PhonePreferences.privacyDefault(in: unitOnly))
        XCTAssertNil(PhonePreferences.hrZoneCutoffs(in: unitOnly))

        let zonesOnly: [String: Any] = ["hr_zone_cutoffs": [Int]()]
        XCTAssertEqual(PhonePreferences.hrZoneCutoffs(in: zonesOnly), [])
        XCTAssertNil(PhonePreferences.preferredUnit(in: zonesOnly))
        XCTAssertNil(PhonePreferences.audioCues(in: zonesOnly))
    }
}
