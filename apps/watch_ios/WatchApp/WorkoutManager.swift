import Foundation
import CoreLocation
import HealthKit
import WatchKit
import WidgetKit

/// Manages run recording: timer, GPS tracking, distance and pace calculation.
class WorkoutManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State {
        case idle
        case recovering
        case recording
        case paused
        case finished
    }

    @Published var state: State = .idle
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var distanceMetres: Double = 0
    @Published var currentPace: Double? = nil

    /// What the runner picked before starting. Drives both the
    /// `HKWorkoutConfiguration` the session is opened with and the
    /// `activity_type` the finished run is stamped with — see
    /// `RunActivityType`.
    @Published private(set) var activityType: RunActivityType = DefaultActivityType.stored() ?? .run

    /// Set once the runner picks on the wrist, after which a default the phone
    /// pushes no longer moves the picker.
    private(set) var activityTypePickedOnWrist = false

    func pickActivityType(_ type: RunActivityType) {
        activityType = type
        activityTypePickedOnWrist = true
    }

    /// Prime the picker with the phone's `default_activity_type`.
    func applyDefaultActivityType(_ preferred: RunActivityType) {
        activityType = DefaultActivityType.primed(
            current: activityType,
            default: preferred,
            isIdle: state == .idle,
            pickedOnWrist: activityTypePickedOnWrist
        )
    }

    /// Count of every GPS fix recorded this run. The track itself is never
    /// held in memory: it streams to disk through `CheckpointStore`, because
    /// a 100-hour ultra at 1 Hz is ~360k points. This never resets mid-run,
    /// so the UI and the crash checkpoint report the true number of points.
    @Published var trackPointCount: Int = 0

    /// Live pace's look-back over the estimator's distance; see `PaceWindow`.
    private var paceWindow = PaceWindow()

    /// Off-route guidance for the route the phone armed, or nil when this run
    /// is unguided. Built once at `start()` and fed from the GPS stream as an
    /// auxiliary (L4) effect — see `didUpdateLocations`.
    @Published var routeNavigator: RouteNavigator?

    /// Live race mode's auxiliary (L4) seam, handed over by `ContentView`.
    /// Both halves default to no-ops, so the recorder runs with no transport
    /// wired and nothing a failed race effect does can reach the run — see
    /// `LiveRaceRelay`.
    var liveRaceRelay = LiveRaceRelay()

    /// The armed route as the mini-map draws it, empty for an unguided run.
    /// Held apart from `routeNavigator`, which consumes the line and publishes
    /// only its projection of the current fix.
    @Published var mapRoute: [MiniMapPoint] = []

    /// The mini-map's own bounded breadcrumb of the run: the recorder holds
    /// no track in memory to draw from — see `MiniMapTrail`.
    @Published var mapTrail = MiniMapTrail()

    /// The last accepted fix, or nil while this run has none.
    @Published var mapPosition: MiniMapPoint?

    /// What the run screen says about GPS. Recomputed on the elapsed-time
    /// tick rather than on arriving fixes, because the state it reports is
    /// the absence of arriving fixes — a signal derived from the thing that
    /// stopped can only report the stop by never updating again.
    @Published private(set) var gpsBanner: GpsBannerState = .noFixYet
    /// Lap marks the runner has taken this run, cumulative — see `LapMark`.
    @Published var lapMarks: [LapMark] = []

    /// Steps taken this run, or nil while nothing has measured any. Advanced
    /// only while `.recording`, matching Wear OS, which drops a pedometer
    /// emission that arrives paused.
    @Published var steps: Int?

    /// The completed run data, available after stop() or recovery.
    var finishedRun: FinishedRun?

    let healthKit = HealthKitManager()
    private let pedometer = Pedometer()
    /// Spoken split / pace cues. An L4 auxiliary effect: every call below
    /// is made AFTER the core values are committed and none is awaited, so a
    /// speech failure cannot reach the clock, the distance or the track.
    /// `var` so a test can swap the speech seam — see `RunAnnouncer.speak`.
    var announcer = RunAnnouncer()

    var targetPaceSecondsPerKm: Double? = nil

    private let locationManager = CLLocationManager()
    // Reused across every GPS fix — ISO8601DateFormatter is expensive to
    // construct (backing NSDateFormatter + ICU state), so allocating one per
    // point in the ~1 Hz didUpdateLocations callback churned the allocator on
    // the recording hot path over a long run. Mirrors CheckpointStore's static
    // encoder/decoder reuse; the serial CoreLocation delegate makes it safe.
    private let iso8601 = ISO8601DateFormatter()
    private var timer: Timer?
    private var checkpointTimer: Timer?
    private var startDate: Date?
    private var pausedAt: Date?
    private var totalPausedInterval: TimeInterval = 0
    /// One clock for both directions — see `PaceAlertGate.rateLimitSeconds`.
    private var lastPaceAlertAt: Date? = nil
    private var currentRunId: String?
    private var checkpointStore: CheckpointStore?

    /// `metadata.distance_estimator` for every run this build records.
    static let distanceEstimatorTag = "kalman_v1"

    /// The spec-v1 estimator for the CURRENT active segment. A pause banks the
    /// segment and the next one starts on a fresh estimator, so neither the
    /// paused span nor the wander across it can be credited — the first fix
    /// after resume anchors and credits nothing, the old `#371` contract.
    private(set) var distanceEstimator = GpsDistanceEstimator()
    /// Distance banked by segments closed at a pause.
    private var bankedDistanceMetres: Double = 0
    private var bankedStepFilledMetres: Double = 0
    /// Estimator clock of the last fix fed, used to seal the pace window when
    /// the estimator re-anchors over a gap it will not credit.
    private var lastEstimatorFixT: Double?

    var distanceStepFilledMetres: Double {
        bankedStepFilledMetres + distanceEstimator.stepDistanceM
    }

    /// A cyclist outruns the running cap, so the cap follows the picker.
    static func maxSpeedMps(for activity: RunActivityType) -> Double {
        activity == .cycle ? 25.0 : 10.0
    }

    /// `ProcessInfo.systemUptime` of the last fix that passed the accuracy
    /// gate — the banner's clock. See `GpsHealth` for why it is not the same
    /// clock the self-heal retry reads.
    private var lastAcceptedFixUptime: TimeInterval?
    /// Uptime of the last `didUpdateLocations` of any kind — the retry's clock.
    private var lastGpsDeliveryUptime: TimeInterval?
    /// Uptime of the last (re)start of location updates.
    private var lastGpsRetryUptime: TimeInterval?
    private var locationUpdatesRunning = false
    private var gpsRetryTimer: Timer?

    struct FinishedRun {
        let id: String
        let startedAt: Date
        let durationSeconds: Int
        let distanceMetres: Double
        /// The run's NDJSON track file. The trace is carried as a path, not
        /// as an array: a 100-hour ultra is ~360k points, and a resident
        /// array of them (plus the encode that follows) is what made the old
        /// finish path an OOM risk. Every consumer streams from here.
        let trackFileURL: URL
        let trackPointCount: Int
        let averageBPM: Double?
        /// What the runner picked before starting, or what a recovered
        /// checkpoint recorded. Rides to the row as `activity_type`.
        let activityType: RunActivityType
        /// The share of the run's active time the heart-rate sensor was
        /// delivering, or nil when nothing measured it. Taken from the SAME
        /// `heartRateClaim` call as `averageBPM` — the two are one statement
        /// about one run, and grading twice could publish a coverage that
        /// contradicts the average it suppressed.
        let hrCoverage: Double?
        /// Steps this run, or nil when nothing measured any — see `Pedometer`.
        let steps: Int?
        /// The run's splits, already in the registered per-lap shape. Empty
        /// when the runner marked none.
        let laps: [RunLap]
        /// The runner's `privacy_default` as a `runs.is_public` snapshot,
        /// taken when the run stopped so a later change on the phone cannot
        /// re-classify a run already recorded. Nil when the phone never said,
        /// which omits the key and leaves the row private.
        var isPublic: Bool? = nil
        /// `metadata.distance_estimator`: which algorithm produced
        /// `distanceMetres`. Nil for a recovered run whose checkpoint predates
        /// the estimator, which omits the key rather than mislabel a hop-sum.
        var distanceEstimator: String? = nil
        /// Metres the pedometer filled across GPS gaps, already inside
        /// `distanceMetres`. Sent only when above zero.
        var distanceStepFilledMetres: Double = 0
    }

    /// A track point in the wire shape the phone, web and mobile clients
    /// read — distinct from the on-disk `TrackPointRecord` only in that `ts`
    /// is nullable there. Produced one at a time by `writeTrackJSON()`.
    struct TrackPoint: Codable {
        let lat: Double
        let lng: Double
        let ele: Double?
        let ts: String?
        var accuracyMetres: Double? = nil
        var speedMps: Double? = nil
        var speedAccuracyMps: Double? = nil
        var bearingDeg: Double? = nil
    }

    /// Bytes buffered before `writeTrackJSON` flushes to the output handle.
    private static let trackJSONFlushBytes = 64 * 1024

    /// Write the finished run's track to a JSON file in the durable payload
    /// directory and return the URL, suitable for `WCSession.transferFile`.
    /// The phone gzips + uploads to Supabase Storage on receipt.
    ///
    /// Durable rather than `Caches` because `WCSession` reads this file off
    /// disk for as long as the transfer is outstanding — which can be days
    /// with the phone switched off — and by then `reset()` has deleted the
    /// NDJSON it was built from, so a purge here loses the run.
    ///
    /// Streams NDJSON line → wire point → output handle, so the peak is one
    /// buffer rather than the whole track plus its encoding. Assembled in a
    /// `.tmp` sibling and renamed, which keeps the all-or-nothing guarantee
    /// the previous `Data.write(options: .atomic)` gave.
    func writeTrackJSON() throws -> URL {
        guard let run = finishedRun else {
            throw NSError(domain: "WorkoutManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No finished run"])
        }
        let dir = RunPayloadStorage.directory
        RunPayloadStorage.createDirectory(at: dir)
        let url = dir.appendingPathComponent("\(run.id).json")
        let tmp = dir.appendingPathComponent("\(run.id).json.tmp")

        try? FileManager.default.removeItem(at: tmp)
        guard FileManager.default.createFile(atPath: tmp.path, contents: nil) else {
            throw NSError(
                domain: "WorkoutManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not create \(tmp.lastPathComponent)"]
            )
        }
        let out = try FileHandle(forWritingTo: tmp)
        let encoder = JSONEncoder()
        let comma = Data(",".utf8)
        var buffer = Data("[".utf8)
        var wroteAny = false
        var failure: Error?

        CheckpointStore.forEachTrackPoint(in: run.trackFileURL) { record in
            guard failure == nil else { return }
            let point = TrackPoint(
                lat: record.lat,
                lng: record.lng,
                ele: record.ele,
                ts: record.ts,
                accuracyMetres: record.accuracyMetres,
                speedMps: record.speedMps,
                speedAccuracyMps: record.speedAccuracyMps,
                bearingDeg: record.bearingDeg
            )
            guard let encoded = try? encoder.encode(point) else { return }
            if wroteAny { buffer.append(comma) }
            buffer.append(encoded)
            wroteAny = true
            guard buffer.count >= WorkoutManager.trackJSONFlushBytes else { return }
            do {
                try out.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            } catch {
                failure = error
            }
        }

        if failure == nil {
            do {
                buffer.append(Data("]".utf8))
                try out.write(contentsOf: buffer)
                try out.synchronize()
            } catch {
                failure = error
            }
        }
        try? out.close()

        if let failure {
            try? FileManager.default.removeItem(at: tmp)
            throw failure
        }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tmp, to: url)
        return url
    }

    override init() {
        super.init()
        // Before anything reads a payload: create the durable directory and
        // carry across whatever an older build left in Caches, so an upgrade
        // over an install with an unsynced run does not orphan it.
        RunPayloadStorage.prepare()
        locationManager.delegate = self
        // The phone recorder's bestForNavigation (#1090): the strongest GPS
        // request CoreLocation takes. Its battery cost on the wrist against
        // kCLLocationAccuracyBest has not been measured on a device yet.
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
        // allowsBackgroundLocationUpdates is set in start(), not here:
        // CoreLocation traps (CLClientIsBackgroundable) if it's enabled before
        // the app is actually running a backgroundable session, which crashes
        // the app the instant WorkoutManager is constructed (e.g. the XCTest
        // host launch). Enable it only when we begin background updates.
    }

    // MARK: - Controls

    func checkForPendingRecovery() {
        // Only from idle: a run continued on a surviving workout session has
        // already rewritten the checkpoint, and must not be offered back to
        // the runner as an unsaved one.
        guard state == .idle, CheckpointStore.peekCheckpoint() != nil else { return }
        state = .recovering
    }

    func start() {
        let runId = UUID().uuidString.lowercased()
        currentRunId = runId
        trackPointCount = 0
        distanceMetres = 0
        elapsedSeconds = 0
        currentPace = nil
        finishedRun = nil
        pausedAt = nil
        totalPausedInterval = 0
        lastPaceAlertAt = nil
        resetDistanceEstimator()
        announcer.reset()
        armRouteGuidance()
        mapTrail.reset()
        mapPosition = nil
        lapMarks = []
        steps = nil
        healthKit.reset()

        let store = CheckpointStore(runId: runId)
        checkpointStore = store
        CheckpointStore.purgeTrackFiles(except: store.trackFileURL)
        RunPayloadStorage.sweepStaleExports(
            pending: WatchConnectivityManager.shared.pendingTransferURLs()
        )

        lastAcceptedFixUptime = nil
        lastGpsDeliveryUptime = nil
        gpsBanner = .noFixYet
        locationManager.requestWhenInUseAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        startLocationUpdates()
        healthKit.startWorkout(activityType: activityType.healthKitActivityType)

        let start = Date()
        startDate = start
        startPedometer(from: start, priorSteps: nil)
        startRecordingTimers()

        state = .recording
        publishComplicationSnapshot()
        announcer.announceStart()
    }

    /// The armed route's guidance and its map line, from whatever the phone
    /// last armed.
    private func armRouteGuidance() {
        let armedRoute = ArmedRouteStore.load()
        routeNavigator = armedRoute.map { RouteNavigator(routePoints: $0.locations) }
        mapRoute = armedRoute?.coordinates.map {
            MiniMapPoint(latitude: $0.latitude, longitude: $0.longitude)
        } ?? []
    }

    /// `priorSteps` is what a continued run had counted before the app was
    /// terminated. The pedometer is re-baselined at the relaunch rather than
    /// asked for history from the run's start, because its baseline is what
    /// keeps a device total from ever reaching a row — so steps taken across
    /// the termination itself are not counted, and the figure errs low.
    private func startPedometer(from start: Date, priorSteps: Int?) {
        // Dropped while paused rather than suspended, mirroring Wear OS: the
        // counter is cumulative on both platforms, so stopping it would not
        // exclude the steps taken during the pause anyway — it would only make
        // the figure disagree between the two wrists.
        pedometer.start(from: start) { [weak self] counted in
            guard let self, self.state == .recording else { return }
            let steps = (priorSteps ?? 0) + counted
            self.steps = steps
            self.distanceEstimator.addSteps(
                t: ProcessInfo.processInfo.systemUptime,
                cumulativeSteps: steps
            )
        }
    }

    private func startRecordingTimers() {
        timer?.invalidate()
        checkpointTimer?.invalidate()
        gpsRetryTimer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let startDate = self.startDate else { return }
            guard self.state == .recording else { return }
            self.elapsedSeconds = Date().timeIntervalSince(startDate) - self.totalPausedInterval
            // After the elapsed write, before anything else: the banner is an
            // L4 disclosure about L1, and the L0 clock it rides on must be
            // committed whatever it says. Pure value maths over a stamp the
            // GPS delegate wrote — no framework call, nothing to fail.
            self.refreshGpsBanner()
            // Heart-rate coverage advances on THIS clock, not on HealthKit's
            // deliveries: the gap it measures is a stream that has gone quiet,
            // and a quiet stream emits nothing to hang the measurement on.
            // Inside the `.recording` guard, so a pause neither credits
            // coverage nor charges the run for it (decisions § 1156).
            self.healthKit.advanceCoverage(activeElapsedSeconds: self.elapsedSeconds)
        }

        checkpointTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.writeCheckpoint()
        }

        gpsRetryTimer = Timer.scheduledTimer(
            withTimeInterval: GpsHealth.retryIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            self?.selfHealGps()
        }
    }

    // MARK: - Continuing a run after the app was terminated

    /// Whether the pending checkpoint can be continued, not only saved.
    var canContinueRecoveredRun: Bool {
        guard let cp = CheckpointStore.peekCheckpoint() else { return false }
        return RunResumePlan.canContinue(cp, now: Date())
    }

    /// watchOS relaunched the app into a workout session that outlived it.
    /// Continue the checkpointed run on that session — no prompt, because the
    /// runner never stopped — or, when there is no run of ours to continue,
    /// end the session so Health does not file a workout nobody recorded.
    func adoptSurvivingWorkout(_ survivor: HKWorkoutSession) {
        guard state == .idle || state == .recovering,
              continueRecoveredRun(recoveredSession: survivor) else {
            healthKit.endOrphanedSession(survivor)
            return
        }
    }

    /// Pick the checkpointed run up where it stopped and keep recording it
    /// under the SAME id, into the SAME track file — one run on the phone,
    /// not two. Returns false when there is nothing continuable, leaving the
    /// recovery prompt's other two answers as they were.
    ///
    /// The restore is committed before any framework is touched, and each
    /// source is restarted on its own after it: a session that will not open
    /// or a pedometer that will not start costs its own figure, never the
    /// clock, the distance or the track the run already has.
    @discardableResult
    func continueRecoveredRun(recoveredSession: HKWorkoutSession? = nil, now: Date = Date()) -> Bool {
        guard let cp = CheckpointStore.peekCheckpoint(),
              RunResumePlan.canContinue(cp, now: now) else { return false }
        let plan = RunResumePlan.make(
            checkpoint: cp,
            now: now,
            workoutSessionSurvived: recoveredSession != nil
        )
        restoreRun(from: cp, plan: plan)

        let prior = RunResumePlan.heartRatePrior(cp, resumingAt: plan.elapsedSeconds)
        if let recoveredSession {
            healthKit.adoptRecoveredWorkout(recoveredSession, resuming: prior)
        } else {
            healthKit.startWorkout(activityType: activityType.healthKitActivityType, resuming: prior)
        }
        if plan.resumesPaused {
            healthKit.pauseSession()
        } else {
            locationManager.requestWhenInUseAuthorization()
            locationManager.allowsBackgroundLocationUpdates = true
            startLocationUpdates()
        }
        startPedometer(from: now, priorSteps: cp.steps)
        startRecordingTimers()
        // The checkpoint now describes the resumed clock, so a second
        // termination before the next tick resumes from here and not from
        // the first one's arithmetic again.
        writeCheckpoint()
        publishComplicationSnapshot()
        return true
    }

    /// Everything a continued run carries over, as plain state — no
    /// framework call, so the test host exercises all of it.
    ///
    /// The distance is banked as a closed segment: no fix was recorded across
    /// the termination, so the first fix after it anchors a fresh one and
    /// credits nothing for the span, the same contract a pause keeps (#371).
    /// The mini-map's trail is rebuilt by streaming the track file the run
    /// kept writing, so the map shows the whole run rather than only what
    /// follows the relaunch, at the trail's own flat memory.
    func restoreRun(from cp: RunCheckpoint, plan: RunResumePlan) {
        currentRunId = cp.id
        activityType = RunActivityType.parse(cp.activityType)
        startDate = cp.startedAt
        totalPausedInterval = plan.totalPausedInterval
        pausedAt = plan.pausedAt
        elapsedSeconds = plan.elapsedSeconds
        finishedRun = nil
        currentPace = nil
        lastPaceAlertAt = nil

        resetDistanceEstimator()
        bankedDistanceMetres = cp.distanceMetres.isFinite ? max(cp.distanceMetres, 0) : 0
        bankedStepFilledMetres = cp.distanceStepFilledMetres ?? 0
        distanceMetres = bankedDistanceMetres
        lapMarks = cp.laps ?? []
        steps = cp.steps

        let store = CheckpointStore(runId: cp.id)
        checkpointStore = store
        var trail = MiniMapTrail()
        var count = 0
        var last: TrackPointRecord?
        store.forEachTrackPoint { record in
            count += 1
            trail.append(MiniMapPoint(latitude: record.lat, longitude: record.lng))
            last = record
        }
        trackPointCount = count
        mapTrail = trail
        mapPosition = last.map { MiniMapPoint(latitude: $0.lat, longitude: $0.lng) }

        armRouteGuidance()
        announcer.reset()
        announcer.primeSplits(distanceMetres: distanceMetres)

        lastAcceptedFixUptime = nil
        lastGpsDeliveryUptime = nil
        gpsBanner = .noFixYet
        state = plan.resumesPaused ? .paused : .recording
    }

    /// Record a lap at the current position. Ignored unless the run is
    /// actually recording — a mark taken while paused would open a split the
    /// clock is not advancing through, which Wear OS refuses for the same
    /// reason. Checkpointed immediately: the 15 s tick is a long time to hold
    /// an act the runner has already performed and can see on screen.
    func markLap() {
        guard state == .recording else { return }
        lapMarks.append(LapMark(
            index: lapMarks.count + 1,
            atSeconds: elapsedSeconds,
            distanceMetres: distanceMetres
        ))
        writeCheckpoint()
    }

    func pause() {
        guard state == .recording else { return }
        sealDistanceSegment()
        // Capture the frozen state once, while still .recording, so a crash
        // during a long pause recovers the exact pause-boundary values. The
        // periodic timer then skips writes until resume (see writeCheckpoint).
        // `pausedAt` is stamped first so the checkpoint records that the run
        // was paused: a run continued after a termination resumes paused
        // instead of crediting the pause as running time.
        pausedAt = Date()
        writeCheckpoint()
        stopLocationUpdates()
        healthKit.pauseSession()
        state = .paused
        publishComplicationSnapshot()
    }

    func resume() {
        guard state == .paused, let pausedAt else { return }
        totalPausedInterval += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        sealPaceWindow()
        startLocationUpdates()
        healthKit.resumeSession()
        state = .recording
        // Clears the pause from the checkpoint at once rather than up to 15 s
        // later: a run terminated in that window would otherwise resume paused.
        writeCheckpoint()
        publishComplicationSnapshot()
    }

    func stop() {
        if state == .paused, let pausedAt {
            totalPausedInterval += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        timer?.invalidate()
        timer = nil
        gpsRetryTimer?.invalidate()
        gpsRetryTimer = nil
        stopLocationUpdates()
        healthKit.stopWorkout()
        pedometer.stop()
        if state == .recording { sealDistanceSegment() }

        // The full run stays on disk — nothing here materialises it. Close the append
        // handle so every fix is flushed, then hand the finished run the
        // file; `writeTrackJSON` streams from it at sync time.
        let store = checkpointStore
        store?.closeAppendHandle()
        // Only the metadata checkpoint is dropped: leaving it would offer
        // "Recover unsaved run?" for a run the user has just finished. The
        // NDJSON survives until reset(), because it IS the finished run's
        // payload.
        CheckpointStore.clearStatic()
        checkpointStore = nil

        let duration = Int(elapsedSeconds)

        // One UUID per run: the finished run reuses the id assigned at
        // start() — the same id the checkpoint and the on-disk track file
        // are keyed under — instead of minting a fresh one here, which
        // previously orphaned the streamed track from the run row.
        let runId = currentRunId ?? UUID().uuidString.lowercased()
        // Graded, never the raw mean: a mean taken over less of the run than
        // not is not the run's average, and every reader of `avg_bpm` treats
        // it as though it were (decisions § 1083). Taken once — the claim's
        // two halves have to describe the same grading or the row can say the
        // sensor covered a third of the run while carrying that third's mean
        // as the run's average.
        let claim = healthKit.heartRateClaim(activeElapsedSeconds: elapsedSeconds)
        finishedRun = FinishedRun(
            id: runId,
            startedAt: startDate ?? Date(),
            durationSeconds: duration,
            distanceMetres: distanceMetres,
            trackFileURL: store?.trackFileURL ?? CheckpointStore.trackFile(runId: runId),
            trackPointCount: trackPointCount,
            averageBPM: claim.averageBPM,
            activityType: activityType,
            hrCoverage: claim.coverage,
            steps: steps,
            laps: RunLaps.splits(
                marks: lapMarks,
                totalDistanceMetres: distanceMetres,
                totalDurationSeconds: duration
            ),
            isPublic: PrivacyDefault.isPublic(PrivacyDefault.stored()),
            distanceEstimator: Self.distanceEstimatorTag,
            distanceStepFilledMetres: distanceStepFilledMetres
        )

        state = .finished
        publishComplicationSnapshot()
        announcer.announceFinish(distanceMetres: distanceMetres, durationSeconds: duration)

        // Auxiliary (L4), and last: the run is banked in `finishedRun`, its
        // track is closed on disk and the summary screen already has it
        // before the race hears about it. `LiveRaceState.finish` returns
        // nothing to send unless a race was actually running, and reports
        // once.
        if let run = finishedRun {
            liveRaceRelay.finish(RaceFinish(
                runId: run.id,
                durationSeconds: run.durationSeconds,
                distanceMetres: run.distanceMetres
            ))
        }
    }

    func reset() {
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        gpsRetryTimer?.invalidate()
        gpsRetryTimer = nil
        pedometer.stop()
        checkpointStore?.closeAppendHandle()
        // The finished run's NDJSON is its payload and outlived stop(); back
        // at idle nothing can still want it.
        if let trackFileURL = finishedRun?.trackFileURL {
            try? FileManager.default.removeItem(at: trackFileURL)
        }
        trackPointCount = 0
        distanceMetres = 0
        elapsedSeconds = 0
        currentPace = nil
        finishedRun = nil
        pausedAt = nil
        totalPausedInterval = 0
        lastPaceAlertAt = nil
        resetDistanceEstimator()
        announcer.reset()
        lastAcceptedFixUptime = nil
        lastGpsDeliveryUptime = nil
        gpsBanner = .noFixYet
        routeNavigator = nil
        mapRoute = []
        mapTrail.reset()
        mapPosition = nil
        lapMarks = []
        steps = nil
        checkpointStore = nil
        currentRunId = nil
        state = .idle
        publishComplicationSnapshot()
    }

    /// Push the active-run snapshot to the App-Group container that
    /// the complication widget extension reads from. The widget
    /// extension lives in its own process and can't observe
    /// `@Published` properties directly, so this is the handoff
    /// point. After writing we also nudge `WidgetCenter` so the
    /// platform replaces the previous timeline immediately rather
    /// than waiting up to ~30 minutes for the next natural refresh.
    /// Called on every state transition (start / pause / resume /
    /// stop / reset) — see ActiveRunComplicationBundle for the
    /// reader side.
    private func publishComplicationSnapshot() {
        let isActive = state == .recording || state == .paused
        let snapshot = ActiveRunSnapshot(
            isActive: isActive,
            elapsedSeconds: Int(elapsedSeconds),
            distanceMeters: distanceMetres,
            paceSecPerKm: currentPace,
            lastUpdatedEpoch: Date().timeIntervalSince1970,
        )
        ActiveRunBridge.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: ActiveRunBridge.complicationKind)
    }

    // MARK: - Formatting

    var formattedElapsed: String {
        let h = Int(elapsedSeconds) / 3600
        let m = (Int(elapsedSeconds) % 3600) / 60
        let s = Int(elapsedSeconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    var formattedDistance: String {
        RunFormat.distance(metres: distanceMetres, fractionDigits: 2)
    }

    var formattedPace: String {
        RunFormat.pace(secondsPerKm: currentPace)
    }

    // MARK: - GPS self-heal

    private var locationAuthorized: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    private func startLocationUpdates() {
        locationManager.startUpdatingLocation()
        locationUpdatesRunning = true
        lastGpsRetryUptime = ProcessInfo.processInfo.systemUptime
    }

    private func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationUpdatesRunning = false
    }

    /// Restart location updates when `GpsHealth` says the stream is not going
    /// to recover on its own. An auxiliary (L4) watchdog over an L1 source:
    /// it can only ever re-issue a CoreLocation call, and the clock, the
    /// elapsed readout and the on-disk track are untouched whether it fires
    /// or not.
    private func selfHealGps() {
        guard state == .recording else { return }
        guard let trigger = GpsHealth.retryTrigger(
            authorized: locationAuthorized,
            updatesRunning: locationUpdatesRunning,
            lastDeliveryUptime: lastGpsDeliveryUptime,
            lastRetryUptime: lastGpsRetryUptime,
            nowUptime: ProcessInfo.processInfo.systemUptime
        ) else { return }
        // A subscription that has gone quiet is still registered, so asking a
        // live manager to start again is a no-op — the quiet one has to be
        // torn down first for the restart to mean anything.
        if trigger == .stalled { locationManager.stopUpdatingLocation() }
        startLocationUpdates()
    }

    func refreshGpsBanner() {
        let age = lastAcceptedFixUptime.map { ProcessInfo.processInfo.systemUptime - $0 }
        gpsBanner = GpsHealth.banner(lastAcceptedFixAge: age)
    }

    // MARK: - CLLocationManagerDelegate

    /// CoreLocation reporting it cannot produce a fix. `.locationUnknown` is
    /// transient — Apple's contract is that the manager keeps trying — so
    /// stopping updates on it would turn a minute under a canopy into a dead
    /// run. Every other code (a revoked authorization, most often) means this
    /// subscription will not deliver again, and `selfHealGps` must not spend
    /// the rest of the run restarting one that cannot produce a fix.
    ///
    /// The recording is untouched either way: the clock, the banked distance
    /// and the track file are all downstream of fixes that already arrived.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        stopLocationUpdates()
    }

    /// The runner denies the prompt at start and relents from Settings mid-run.
    /// That grant arrives here and nowhere else — `GpsHealth.retryTrigger`
    /// deliberately refuses to poll for it, because a restart under a denial
    /// delivers nothing.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard state == .recording else { return }
        if locationAuthorized {
            guard !locationUpdatesRunning else { return }
            startLocationUpdates()
        } else {
            stopLocationUpdates()
        }
    }

    /// Drop the pace look-back so it cannot span a discontinuity.
    ///
    /// Pace is the estimator's distance gained over the look-back divided by
    /// its time span, so any gap the estimator refused to credit would be
    /// timed against metres it never counted. Two places create that gap and
    /// BOTH must seal: a pause (a 20-minute aid-station stop read 1:48:35 /km
    /// and fired a false "too slow" alert — issue #371's defect, fixed for
    /// distance and never applied to pace), and a GPS gap the estimator
    /// re-anchors over. The canonical Flutter recorder seals at both.
    private func sealPaceWindow() {
        paceWindow.seal()
        currentPace = nil
    }

    private func resetDistanceEstimator() {
        distanceEstimator = GpsDistanceEstimator(maxSpeedMps: Self.maxSpeedMps(for: activityType))
        bankedDistanceMetres = 0
        bankedStepFilledMetres = 0
        lastEstimatorFixT = nil
        paceWindow.seal()
    }

    /// Close the active segment at a pause or stop: commit any steps buffered
    /// across a trailing gap, bank the segment, and start the next one fresh
    /// but keeping the learned stride, so a GPS gap right after a resume is
    /// still step-filled.
    private func sealDistanceSegment() {
        distanceEstimator.finish(t: ProcessInfo.processInfo.systemUptime)
        bankedDistanceMetres += distanceEstimator.distanceM
        bankedStepFilledMetres += distanceEstimator.stepDistanceM
        distanceEstimator = distanceEstimator.nextSegment()
        lastEstimatorFixT = nil
        paceWindow.seal()
        distanceMetres = bankedDistanceMetres
    }

    /// The fix's own time on the uptime clock. Each fix keeps its spacing from
    /// its timestamp, so a batched delivery is not collapsed onto one instant,
    /// while the batch is pinned to `systemUptime` so a wall-clock step between
    /// deliveries cannot run the estimator's clock backwards for a whole run.
    static func estimatorTime(of location: CLLocation, nowUptime: TimeInterval, now: Date) -> Double {
        nowUptime + location.timestamp.timeIntervalSince(now)
    }

    /// CoreLocation reports an unknown speed, course or accuracy as a
    /// negative value; each reads as absent here, for the estimator and for
    /// the stored track point alike.
    static func speed(of location: CLLocation) -> Double? {
        location.speed >= 0 ? location.speed : nil
    }

    static func speedAccuracy(of location: CLLocation) -> Double? {
        location.speedAccuracy >= 0 ? location.speedAccuracy : nil
    }

    static func bearing(of location: CLLocation) -> Double? {
        location.course >= 0 && location.courseAccuracy >= 0 ? location.course : nil
    }

    private func feedEstimator(_ location: CLLocation, t: Double) {
        distanceEstimator.addFix(
            t: t,
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy,
            speedMps: Self.speed(of: location),
            speedAccuracyMps: Self.speedAccuracy(of: location),
            bearingDeg: Self.bearing(of: location)
        )
        distanceMetres = bankedDistanceMetres + distanceEstimator.distanceM
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Stamped before the accuracy gate: a delivery of 100 m fixes proves
        // the subsystem is alive, and restarting CoreLocation cannot clear a
        // tree canopy. The banner reads the ACCEPTED stamp below instead,
        // because the runner's distance is frozen either way.
        if !locations.isEmpty { lastGpsDeliveryUptime = ProcessInfo.processInfo.systemUptime }
        var newPoints: [TrackPointRecord] = []
        var lastAcceptedFix: CLLocation?
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let now = Date()
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 30 else { continue }

            // A gap the estimator will re-anchor over is a span it credits
            // nothing for, so the pace look-back must not time across it
            // either — the same seal a pause applies.
            let t = Self.estimatorTime(of: location, nowUptime: nowUptime, now: now)
            if let lastT = lastEstimatorFixT, t - lastT > distanceEstimator.gapWindowS {
                sealPaceWindow()
            }
            if lastEstimatorFixT.map({ t > $0 }) ?? true { lastEstimatorFixT = t }
            feedEstimator(location, t: t)
            paceWindow.add(t: t, distanceM: distanceEstimator.distanceM)
            lastAcceptedFix = location

            newPoints.append(TrackPointRecord(
                lat: location.coordinate.latitude,
                lng: location.coordinate.longitude,
                ele: location.altitude > -999 ? location.altitude : nil,
                ts: iso8601.string(from: location.timestamp),
                accuracyMetres: location.horizontalAccuracy,
                speedMps: Self.speed(of: location),
                speedAccuracyMps: Self.speedAccuracy(of: location),
                bearingDeg: Self.bearing(of: location)
            ))
        }

        if lastAcceptedFix != nil {
            lastAcceptedFixUptime = ProcessInfo.processInfo.systemUptime
        }

        if !newPoints.isEmpty {
            checkpointStore?.appendTrackPoints(newPoints)
            trackPointCount += newPoints.count
        }

        updatePace()

        // Route guidance runs last, after the distance, the on-disk track and
        // the pace have all been committed — an auxiliary L4 effect that a
        // core L1 recording step never waits on and never shares state with,
        // so a route with no usable geometry costs the run nothing.
        if let navigator = routeNavigator, let fix = lastAcceptedFix {
            navigator.update(currentLocation: fix)
        }

        // The mini-map is the last auxiliary read, and a read only: pure value
        // maths over points the steps above have already committed, with no
        // framework call to fail and nothing the recording stack waits on.
        for record in newPoints {
            mapTrail.append(MiniMapPoint(latitude: record.lat, longitude: record.lng))
        }
        if let fix = lastAcceptedFix {
            mapPosition = MiniMapPoint(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude
            )
        }

        // Spoken split, last of all: by here the distance this cue describes
        // is already banked, already on disk and already on screen, so the
        // runner's record does not depend on anything the speech engine does.
        announcer.announceSplitIfDue(
            distanceMetres: distanceMetres, paceSecondsPerKm: currentPace
        )
        // The live-race ping is the OUTERMOST auxiliary effect (L4) — a
        // network hop over Watch Connectivity, reached only once the
        // distance, the on-disk track, the pace, the route guidance and the
        // map are all committed. The seam is handed a value and returns
        // nothing, and the transport behind it swallows its own failure with
        // a log, so a race the phone cannot be told about costs the
        // recording nothing. The cadence gate lives in `LiveRaceState`, not
        // here: a fix is offered, not sent.
        if state == .recording, let fix = lastAcceptedFix {
            liveRaceRelay.ping(RacePingSample(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                distanceMetres: distanceMetres,
                elapsedSeconds: Int(elapsedSeconds),
                bpm: healthKit.currentBPM,
                uptime: ProcessInfo.processInfo.systemUptime
            ))
        }
    }

    private func writeCheckpoint() {
        // While paused nothing in the checkpoint changes — distance and the
        // active-duration clock are both frozen — so the 15s timer would
        // re-write (and fsync) identical bytes every tick across a long
        // pause. The pause boundary is captured once by pause() before the
        // state flips; skip the no-op churn until recording resumes.
        guard state == .recording else { return }
        guard let store = checkpointStore,
              let runId = currentRunId,
              let start = startDate else { return }
        // Graded against coverage SO FAR, on the same clock the checkpoint
        // stamps its own duration from — so a crash-recovered run carries the
        // claim it would have carried had it been stopped here, rather than an
        // ungraded mean the recovery path has no way to grade.
        let claim = healthKit.heartRateClaim(activeElapsedSeconds: elapsedSeconds)
        let measured = healthKit.checkpointMeasurement
        let cp = RunCheckpoint(
            id: runId,
            startedAt: start,
            distanceMetres: distanceMetres,
            activeDurationSeconds: elapsedSeconds,
            pausedIntervalSeconds: totalPausedInterval,
            trackPointCount: trackPointCount,
            cacheFileURL: store.trackFileURL,
            averageBPM: claim.averageBPM,
            hrCoverage: claim.coverage,
            steps: steps,
            laps: lapMarks,
            activityType: activityType.rawValue,
            isPublic: PrivacyDefault.isPublic(PrivacyDefault.stored()),
            distanceEstimator: Self.distanceEstimatorTag,
            distanceStepFilledMetres: distanceStepFilledMetres,
            pausedAt: pausedAt,
            hrMeanUngraded: measured.mean,
            hrCoveredSeconds: measured.coveredSeconds
        )
        store.write(checkpoint: cp)
        // Match the track's crash-durability window to the checkpoint's.
        store.syncTrack()
    }

    func recoverRun() -> FinishedRun? {
        guard let cp = CheckpointStore.peekCheckpoint() else { return nil }
        let store = CheckpointStore(runId: cp.id)
        // Counted off the file rather than taken from `cp.trackPointCount`:
        // fixes appended since the last 15 s checkpoint are on disk but not
        // in the checkpoint's own figure.
        let count = store.countTrackPoints()
        trackPointCount = count
        let marks = cp.laps ?? []
        lapMarks = marks
        steps = cp.steps
        return FinishedRun(
            id: cp.id,
            startedAt: cp.startedAt,
            durationSeconds: Int(cp.activeDurationSeconds),
            distanceMetres: cp.distanceMetres,
            trackFileURL: store.trackFileURL,
            trackPointCount: count,
            // Restored from the checkpoint so a recovered run keeps its
            // heart-rate summary instead of dropping to "— bpm".
            averageBPM: cp.averageBPM,
            activityType: RunActivityType.parse(cp.activityType),
            // A checkpoint from a build that never carried the field decodes
            // as nil, and nil rides through to the row as an OMITTED key —
            // never as a zero, which would claim the sensor delivered nothing.
            hrCoverage: cp.hrCoverage,
            // Same shape of claim for the pedometer: an absent count is a run
            // nothing counted steps for, not a run of no steps (#389).
            steps: cp.steps,
            // The recovered run is being finished HERE, so its trailing split
            // is measured against the checkpoint's own totals — the same
            // arithmetic `stop()` does, against the figures the crash froze.
            laps: RunLaps.splits(
                marks: marks,
                totalDistanceMetres: cp.distanceMetres,
                totalDurationSeconds: Int(cp.activeDurationSeconds)
            ),
            // The visibility in force while the run was recorded, not
            // whatever the phone says now — the stop path's rule, which Wear
            // OS's recovery keeps for the same reason (#389).
            isPublic: cp.isPublic,
            distanceEstimator: cp.distanceEstimator,
            distanceStepFilledMetres: cp.distanceStepFilledMetres ?? 0
        )
    }

    func clearRecovery() {
        CheckpointStore.clearStatic()
    }

    private func updatePace() {
        guard let pace = paceWindow.secondsPerKm else { return }
        currentPace = pace
        checkPaceAlert(pace: pace)
    }

    /// The drift threshold and the rate limit both live in `PaceAlertGate`,
    /// which Wear OS's `PaceAlert.kt` is held to value-for-value.
    private func checkPaceAlert(pace: Double) {
        guard let target = targetPaceSecondsPerKm, distanceMetres > 200 else { return }
        let now = Date()
        let decision = PaceAlertGate.decide(
            targetSecondsPerKm: target,
            currentSecondsPerKm: pace,
            secondsSinceLastAlert: lastPaceAlertAt.map { now.timeIntervalSince($0) }
        )
        guard decision.fire else { return }
        lastPaceAlertAt = now
        WKInterfaceDevice.current().play(.notification)
        announcer.announcePaceAlert(tooSlow: decision.tooSlow)
    }
}

/// Live pace over the GPS distance estimator's last ~200 m.
///
/// Each sample is the estimator's clock and its cumulative distance at a fix,
/// so pace is the filtered distance gained over the window, not the sum of
/// fix-to-fix hops. The hop-sum over-reads by the GPS jitter the estimator
/// removes: a steady 5:00/km with fixes 1.25 m either side of the line sums
/// to 4:00/km, which told the runner to slow down when they were on pace.
/// `seal()` empties the window at every pause, resume and re-anchored gap.
struct PaceWindow {
    static let windowM = 200.0
    static let minWindowM = 50.0
    static let minSamples = 5

    private var samples: [(t: Double, m: Double)] = []
    private var sinceSeal = 0

    mutating func seal() {
        samples.removeAll(keepingCapacity: true)
        sinceSeal = 0
    }

    mutating func add(t: Double, distanceM: Double) {
        guard t.isFinite, distanceM.isFinite else { return }
        if let last = samples.last, t <= last.t { return }
        samples.append((t: t, m: distanceM))
        sinceSeal += 1
        var drop = 0
        while samples.count - drop > 2, distanceM - samples[drop + 1].m >= Self.windowM {
            drop += 1
        }
        if drop > 0 { samples.removeFirst(drop) }
    }

    /// Null until the window since the last seal holds `minSamples` fixes and
    /// `minWindowM`.
    var secondsPerKm: Double? {
        guard sinceSeal >= Self.minSamples, let first = samples.first, let last = samples.last else {
            return nil
        }
        let gained = last.m - first.m
        let seconds = last.t - first.t
        guard gained >= Self.minWindowM, seconds > 0 else { return nil }
        return seconds / gained * 1000
    }
}
