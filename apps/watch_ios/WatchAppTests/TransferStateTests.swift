import XCTest
import WatchConnectivity
@testable import WatchApp

/// `WatchConnectivityManager.TransferState` drives the post-run sync UI
/// (`PostRunView` reads `case .failed(let msg)` and shows the message; the
/// "Sent to phone" / "Queued — will retry" status text switches on it). The
/// Equatable conformance with an associated value is easy to get subtly wrong
/// — two `.failed` with different messages must NOT compare equal — so pin it.
///
/// Tested without constructing the manager (its `init` activates a real
/// `WCSession`, unavailable in the unit-test host); the enum is a value type
/// reachable as a nested type.
final class TransferStateTests: XCTestCase {
    typealias State = WatchConnectivityManager.TransferState

    func testSimpleCasesEqual() {
        XCTAssertEqual(State.idle, State.idle)
        XCTAssertEqual(State.pending, State.pending)
        XCTAssertEqual(State.completed, State.completed)
    }

    func testDistinctSimpleCasesNotEqual() {
        XCTAssertNotEqual(State.idle, State.pending)
        XCTAssertNotEqual(State.pending, State.completed)
        XCTAssertNotEqual(State.completed, State.idle)
    }

    func testFailedEqualOnlyWhenMessageMatches() {
        XCTAssertEqual(State.failed("network down"), State.failed("network down"))
        XCTAssertNotEqual(State.failed("network down"), State.failed("timeout"))
    }

    func testFailedNotEqualToSimpleCases() {
        XCTAssertNotEqual(State.failed("x"), State.idle)
        XCTAssertNotEqual(State.failed("x"), State.completed)
    }

    func testPatternMatchExtractsMessage() {
        // PostRunView relies on `if case .failed(let msg)` to surface the
        // error text — pin that the associated value is recoverable.
        let s = State.failed("Phone unavailable")
        guard case .failed(let msg) = s else {
            return XCTFail("Expected .failed")
        }
        XCTAssertEqual(msg, "Phone unavailable")
    }

    // `transferRun` gates on `WCSession.default.activationState == .activated`
    // and returns a Bool the caller (`ContentView.syncRun`) uses to decide
    // whether to mark the run synced. The activation guard is the whole point
    // of issue #372: a `false` when the session isn't activated is what keeps a
    // finished run from being silently dropped. Constructing the manager would
    // activate a real `WCSession` (unavailable in the unit-test host), so the
    // decision is pulled into the pure `canTransfer` and pinned here.
    func testCanTransferOnlyWhenActivated() {
        XCTAssertTrue(WatchConnectivityManager.canTransfer(activationState: .activated))
    }

    func testCanTransferFalseWhenNotActivated() {
        // The cold-launch window: `WCSession.activate()` hasn't completed.
        XCTAssertFalse(WatchConnectivityManager.canTransfer(activationState: .notActivated))
    }

    func testCanTransferFalseWhenInactive() {
        // A session that went `.inactive` (e.g. phone unpaired mid-session)
        // must also refuse the hand-off so the run is kept for retry.
        XCTAssertFalse(WatchConnectivityManager.canTransfer(activationState: .inactive))
    }

    // A WCSession file transfer outlives the app AND the watch reboot, and
    // waits days for a phone that is switched off — so `queuedCount` and
    // `transferState`, both in-memory, start every launch disagreeing with the
    // outbox. `PreRunView`'s "N run queued to sync" is the only place the watch
    // ever says a run is still waiting, and it renders on `queuedCount > 0`.
    func testActivationWithOutstandingTransfersIsPending() {
        XCTAssertEqual(
            WatchConnectivityManager.stateOnActivation(outstanding: 1),
            .pending,
            "a relaunch over a queued run must not come up idle — the outbox still holds it"
        )
        XCTAssertEqual(WatchConnectivityManager.stateOnActivation(outstanding: 7), .pending)
    }

    func testActivationWithAnEmptyOutboxIsIdle() {
        // And it must not claim pending when nothing is queued, or the watch
        // says "queued — will retry" on a fresh install forever.
        XCTAssertEqual(WatchConnectivityManager.stateOnActivation(outstanding: 0), .idle)
    }
}

/// The phone's settings envelope, decoded fail-closed.
///
/// The watch has read `preferred_unit` out of `UserDefaults` since it
/// shipped and nothing on the phone ever wrote it; the spoken cues arrived
/// with the same hole, which made them unsilenceable from any surface a
/// runner owns. `AppleWatchPrefsBridge` (Dart) -> `WatchIngestBridge`
/// (phone) -> `updateApplicationContext` -> here is the wire that closes it,
/// and this is the end of it a test can reach.
final class PhonePreferencesTests: XCTestCase {

    func testTheWireNamesMatchThePhonesOwnPreferenceKeys() {
        // `preferred_unit` is what the watch reads out of UserDefaults and
        // what `AppleWatchPrefsBridge.push` sends; `audio_cues` is pinned to
        // the phone's `_kAudioCues` by `RunAnnouncerTests`. A rename on
        // either rail is a preference the runner sets that the wrist never
        // sees, with nothing failing anywhere.
        XCTAssertEqual(PhonePreferences.unitKey, "preferred_unit")
        XCTAssertEqual(RunAnnouncer.preferenceKey, "audio_cues")
    }

    // MARK: - the unit

    func testBothUnitsAreAccepted() {
        XCTAssertEqual(PhonePreferences.preferredUnit(in: ["preferred_unit": "km"]), "km")
        XCTAssertEqual(PhonePreferences.preferredUnit(in: ["preferred_unit": "mi"]), "mi")
    }

    func testAnUnknownUnitLeavesTheWristWhereItWas() {
        // Nil is "the phone did not say", which the caller reads as "keep
        // what you have". Falling back to km would make a typo on the phone
        // a metric watch for an imperial runner — on every contact, because
        // the application context is retained and re-offered.
        for rogue in ["KM", "miles", "", "kilometres", "k m"] {
            XCTAssertNil(
                PhonePreferences.preferredUnit(in: ["preferred_unit": rogue]),
                "\(rogue) is not a unit this build knows"
            )
        }
    }

    func testAUnitOfTheWrongTypeIsDropped() {
        XCTAssertNil(PhonePreferences.preferredUnit(in: ["preferred_unit": 1]))
        XCTAssertNil(PhonePreferences.preferredUnit(in: ["preferred_unit": true]))
        XCTAssertNil(PhonePreferences.preferredUnit(in: [:]))
    }

    // MARK: - the cues

    func testBothCueStatesSurvive() {
        XCTAssertEqual(PhonePreferences.audioCues(in: ["audio_cues": false]), false)
        XCTAssertEqual(PhonePreferences.audioCues(in: ["audio_cues": true]), true)
    }

    func testANonBoolCueValueIsDroppedRatherThanCoerced() {
        // The direction that matters: `0` coerced to false silences a runner
        // who never asked for silence, and `"false"` coerced to true keeps
        // talking at one who did.
        for rogue in [0, 1, "false", "true", ""] as [Any] {
            XCTAssertNil(PhonePreferences.audioCues(in: ["audio_cues": rogue]))
        }
    }

    func testAnAbsentCueKeyIsNotAnInstructionToSpeak() {
        // Absent means "unchanged", not "on" — every route push the phone
        // sends arrives with no preferences in it.
        XCTAssertNil(PhonePreferences.audioCues(in: [:]))
        XCTAssertNil(PhonePreferences.audioCues(in: ["route_id": "r1"]))
    }

    // MARK: - independence

    func testEachKeyIsReadWithoutTheOther() {
        // The two ride one envelope from the phone, but the watch must apply
        // whichever it is given: a payload from an older phone build, or a
        // route push, carries one or neither.
        let unitOnly: [String: Any] = ["preferred_unit": "mi"]
        XCTAssertEqual(PhonePreferences.preferredUnit(in: unitOnly), "mi")
        XCTAssertNil(PhonePreferences.audioCues(in: unitOnly))

        let cuesOnly: [String: Any] = ["audio_cues": false]
        XCTAssertNil(PhonePreferences.preferredUnit(in: cuesOnly))
        XCTAssertEqual(PhonePreferences.audioCues(in: cuesOnly), false)
    }
}
