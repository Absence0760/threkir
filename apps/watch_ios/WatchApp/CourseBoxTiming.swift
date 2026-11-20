import Foundation

/// Live park course timing on the wrist (#1446): the server's box rule,
/// matcher v4 (decisions § 2589), run fix by fix as the watch records, so the
/// runner is told "Timing started" when they leave the start box going
/// forward and "Finished!" with their time when they enter the finish box
/// having passed every checkpoint in order within the 25 % length guard.
///
/// A one-way Swift port, not a parity twin: the reference is the phone's
/// batch matcher `_scoreByGates` in `apps/mobile_android/lib/segments.dart`
/// (itself the twin of web `segments.ts` and the server bundle) with the box
/// geometry of `course_gates.dart` (`gateBox`, `gatesShareSpot`,
/// `gateTimingEdges`). The streaming form here keeps every rule of the batch
/// one — the 5 m slack either end, the finish gap rule, laps that never
/// overlap, the fastest lap — and `CourseBoxTimerTests` replays
/// `fixtures/segments_gate_cases.json` and `fixtures/park_course_runs.json`
/// through it and asks for the batch matcher's effort to the millisecond.
/// The server is still the one that writes the time; this is what the runner
/// hears while running.
enum CourseBox {
    /// `kCourseGateBoxDepthM`: how deep a start or finish box is, from its
    /// line.
    static let depthM = 10.0
    /// `kCourseGateSharedSpotM` / `kCourseGateSharedSpotDeg`.
    static let sharedSpotM = 10.0
    static let sharedSpotDeg = 20.0
    /// `kGlobalSegmentBoxSlackM`: the GPS error of a watch standing at the line.
    static let slackM = 5.0
    /// `kGlobalSegmentFinishMaxGapS` and the two `kGlobalSegmentGapSpeed*`.
    static let finishMaxGapS = 300.0
    static let gapSpeedMin = 0.4
    static let gapSpeedMax = 1.5
    /// `kGlobalSegmentLengthTolerance`.
    static let lengthTolerance = 0.25
    /// The matcher's checkpoint tolerance (`toleranceM` default, 35 m).
    static let checkpointToleranceM = 35.0
    /// `kGlobalSegmentMatcherVersion` this port follows.
    static let matcherVersion = 4

    struct Point: Equatable {
        let lat: Double
        let lng: Double
    }

    enum Side { case behind, ahead, centred }

    enum Layout { case apart, shared }

    /// Any finite bearing into [0, 360), as `normalizeBearing`.
    static func normalizeBearing(_ deg: Double) -> Double {
        let b = GateMath.dartMod(GateMath.dartMod(deg, 360) + 360, 360)
        return b >= 360 ? 0 : b
    }

    /// Smallest angle between two bearings, 0...180.
    static func bearingDelta(_ a: Double, _ b: Double) -> Double {
        let d = abs(normalizeBearing(a) - normalizeBearing(b))
        return d > 180 ? 360 - d : d
    }

    static func planeXY(_ origin: Point, _ p: Point) -> (x: Double, y: Double) {
        (
            x: GateMath.rad(GateMath.wrapLng(p.lng - origin.lng)) * GateConstants.earthRadiusM
                * cos(GateMath.rad(origin.lat)),
            y: GateMath.rad(p.lat - origin.lat) * GateConstants.earthRadiusM
        )
    }

    static func fromPlane(_ origin: Point, _ x: Double, _ y: Double) -> Point {
        Point(
            lat: origin.lat + GateMath.deg(y / GateConstants.earthRadiusM),
            lng: GateMath.wrapLng(
                origin.lng
                    + GateMath.deg(x / (GateConstants.earthRadiusM * cos(GateMath.rad(origin.lat))))
            )
        )
    }

    /// The box on one side of a line, `depthM` deep, from `from` to `to`
    /// along it. Corners: the near edge's left then right end (left of
    /// travel), then the far right and far left corners — `gateBox`.
    static func box(
        _ gate: Gate, depthM: Double, side: Side, from: Double = -1, to: Double = 1
    ) -> [Point] {
        let b = GateMath.rad(gate.bearingDeg)
        let ax = gate.halfWidthM * cos(b)
        let ay = -gate.halfWidthM * sin(b)
        let near: Double
        let far: Double
        switch side {
        case .ahead: (near, far) = (0, depthM)
        case .behind: (near, far) = (0, -depthM)
        case .centred: (near, far) = (-depthM / 2, depthM / 2)
        }
        let c = Point(lat: gate.lat, lng: gate.lng)
        func at(_ f: Double, _ k: Double) -> Point {
            fromPlane(c, f * ax + k * sin(b), f * ay + k * cos(b))
        }
        return [at(from, near), at(to, near), at(to, far), at(from, far)]
    }

    /// Whether a start line and a finish line sit at one spot: a loop's or an
    /// out-and-back's — `gatesShareSpot`.
    static func shareSpot(_ start: Gate, _ finish: Gate) -> Bool {
        let p = planeXY(Point(lat: start.lat, lng: start.lng), Point(lat: finish.lat, lng: finish.lng))
        if (p.x * p.x + p.y * p.y).squareRoot() > sharedSpotM { return false }
        let d = bearingDelta(start.bearingDeg, finish.bearingDeg)
        return d <= sharedSpotDeg || d >= 180 - sharedSpotDeg
    }

    /// Whether the end line is also the start line (`linesChain`): on such a
    /// loop with apart boxes, the crossing that finishes a lap starts the next.
    static func linesChain(_ start: Gate, _ end: Gate) -> Bool {
        if GateMath.haversineMetres(start.lat, start.lng, end.lat, end.lng) > start.halfWidthM {
            return false
        }
        let turn = GateMath.dartMod(GateMath.dartMod(end.bearingDeg - start.bearingDeg, 360) + 540, 360) - 180
        return abs(turn) < 90
    }

    /// The edges a course is timed by, read off the drawn boxes —
    /// `gateTimingEdges`.
    struct TimingEdges {
        let layout: Layout
        let startExit: Gate
        let finishEntry: Gate
        let depthM: Double
    }

    private static func edgeGate(_ a: Point, _ b: Point, bearingDeg: Double, halfWidthM: Double) -> Gate {
        let p = planeXY(a, b)
        let mid = fromPlane(a, p.x / 2, p.y / 2)
        return Gate(lat: mid.lat, lng: mid.lng, bearingDeg: normalizeBearing(bearingDeg), halfWidthM: halfWidthM)
    }

    static func timingEdges(_ start: Gate, _ finish: Gate, depthM: Double = depthM) -> TimingEdges {
        if shareSpot(start, finish) {
            let box = box(start, depthM: depthM, side: .centred)
            let sameWay = bearingDelta(start.bearingDeg, finish.bearingDeg) <= 90
            return TimingEdges(
                layout: .shared,
                startExit: edgeGate(box[3], box[2], bearingDeg: start.bearingDeg, halfWidthM: start.halfWidthM),
                finishEntry: sameWay
                    ? edgeGate(box[0], box[1], bearingDeg: start.bearingDeg, halfWidthM: start.halfWidthM)
                    : edgeGate(box[2], box[3], bearingDeg: start.bearingDeg + 180, halfWidthM: start.halfWidthM),
                depthM: depthM
            )
        }
        let s = box(start, depthM: depthM, side: .behind)
        let f = box(finish, depthM: depthM, side: .ahead)
        return TimingEdges(
            layout: .apart,
            startExit: edgeGate(s[0], s[1], bearingDeg: start.bearingDeg, halfWidthM: start.halfWidthM),
            finishEntry: edgeGate(f[0], f[1], bearingDeg: finish.bearingDeg, halfWidthM: finish.halfWidthM),
            depthM: depthM
        )
    }
}

/// What the timer reports as the runner goes.
enum CourseTimingEvent: Equatable {
    /// Left the start box forward with no lap already being timed.
    case started(atMs: Double)
    /// Entered the finish box on a lap that counts.
    case finished(startMs: Double, endMs: Double)

    var finishSeconds: Double? {
        if case let .finished(startMs, endMs) = self { return (endMs - startMs) / 1000 }
        return nil
    }
}

/// The box rule, streamed. Feed it every fix the run stores on its line (the
/// fixes the server's `trackLine` reads — not the ones flagged `offTrack`), in
/// order; `settle()` at Stop applies the "ended inside the finish box" rule.
final class CourseBoxTimer {
    private struct Pending {
        let crossing: GateCrossing
        let fromIdx: Int
        /// Next checkpoint to pass, and the fix index the last one was passed
        /// at: the batch rule's first in-tolerance index at or after the
        /// previous checkpoint's, kept as the fixes arrive.
        var cursor: Int
        var doneIdx: Int?
    }

    private struct FixGap {
        let fromIdx: Int
        let fromMs: Double
        let fromCum: Double
        let gapS: Double
    }

    let edges: CourseBox.TimingEdges
    private let checkpoints: [CourseBox.Point]
    private let toleranceM: Double
    private let minCovered: Double
    private let maxCovered: Double
    private let chained: Bool
    private let startDetector: GateCrossingDetector
    private let endDetector: GateCrossingDetector

    private var pending: [Pending] = []
    private(set) var bestStartMs: Double?
    private(set) var bestEndMs: Double?

    private var idx = -1
    private var cum = 0.0
    private var last: CourseBox.Point?
    private var prevIdx = -1
    private var prevMs = -Double.infinity
    private var prevCum = 0.0
    /// The fixes from the last accepted one up to now, so a start opened on
    /// this fix counts checkpoints from the fix before its crossing, exactly
    /// as the batch rule's `fromIdx` does.
    private var sinceAccepted: [(idx: Int, point: CourseBox.Point)] = []
    private var tail: (idx: Int, ms: Double, cum: Double, gap: FixGap)?
    private var prevEntry = GateProjection(s: .nan, u: .nan)
    private var settled = false

    /// Nil when the course has no usable pair of lines or no length: the
    /// server then times it by its circles, which nothing here follows.
    init?(
        startGate: Gate,
        endGate: Gate,
        distanceM: Double,
        checkpoints: [CourseBox.Point] = [],
        toleranceM: Double = CourseBox.checkpointToleranceM
    ) {
        guard startGate.isUsable, endGate.isUsable, distanceM.isFinite, distanceM > 0 else { return nil }
        let edges = CourseBox.timingEdges(startGate, endGate)
        self.edges = edges
        self.checkpoints = checkpoints
        self.toleranceM = toleranceM
        self.minCovered = distanceM * (1 - CourseBox.lengthTolerance)
        self.maxCovered = distanceM * (1 + CourseBox.lengthTolerance)
        self.chained = edges.layout == .apart && CourseBox.linesChain(startGate, endGate)
        self.startDetector = GateCrossingDetector(edges.startExit)
        self.endDetector = GateCrossingDetector(edges.finishEntry)
    }

    /// The fastest lap so far, in seconds.
    var bestSeconds: Double? {
        guard let s = bestStartMs, let e = bestEndMs else { return nil }
        return (e - s) / 1000
    }

    /// Whether a lap is being timed: the runner has left the start box and
    /// not yet finished.
    var isTiming: Bool { !pending.isEmpty }

    func offer(lat: Double, lng: Double, tMs: Double) -> [CourseTimingEvent] {
        guard !settled, lat.isFinite, lng.isFinite, tMs.isFinite else { return [] }
        let here = CourseBox.Point(lat: lat, lng: lng)
        idx += 1
        let i = idx
        if let last { cum += GateMath.haversineMetres(last.lat, last.lng, lat, lng) }
        last = here

        for k in pending.indices { advance(&pending[k], idx: i, point: here) }
        sinceAccepted.append((i, here))
        if tMs <= prevMs { return [] }

        var events: [CourseTimingEvent] = []
        let entry = edges.finishEntry
        let exit = edges.startExit
        let fix = GateFix(lat: lat, lng: lng, tMs: tMs, coveredM: cum)
        let endCrossing = endDetector.offer(fix)
        let startCrossing = startDetector.offer(fix)

        let gap = FixGap(fromIdx: prevIdx, fromMs: prevMs, fromCum: prevCum, gapS: (tMs - prevMs) / 1000)
        let inFinish = gateProjection(entry, lat, lng)
        if inFinish.s >= -CourseBox.slackM && inFinish.s <= edges.depthM
            && abs(inFinish.u) <= entry.halfWidthM {
            if tail == nil { tail = (i, tMs, cum, gap) }
        } else {
            tail = nil
        }

        let entered: GateCrossing?
        if let endCrossing, endCrossing.direction == .forward {
            entered = endCrossing
        } else if gap.gapS > GateConstants.rejectGapS && gap.gapS <= CourseBox.finishMaxGapS {
            entered = enteredAcrossGap(prev: prevEntry, cur: inFinish, halfWidthM: entry.halfWidthM, fix: fix)
        } else {
            entered = nil
        }
        prevEntry = inFinish

        var closedBy: GateCrossing?
        if let entered, let chosen = pick(endCoveredM: entered.coveredM, endIdx: i, endMs: entered.tMs, gap: gap, endCum: cum) {
            record(chosen.crossing.tMs, entered.tMs)
            events.append(.finished(startMs: chosen.crossing.tMs, endMs: entered.tMs))
            pending = []
            closedBy = entered
        }
        if let closedBy, chained {
            open(closedBy, fromIdx: prevIdx, events: &events)
        }
        if let startCrossing, startCrossing.direction == .forward,
           closedBy == nil || startCrossing.tMs >= closedBy!.tMs {
            open(startCrossing, fromIdx: prevIdx, events: &events)
        } else if prevIdx < 0 {
            // A recording begun on the line: its first fix just past the exit
            // edge starts the clock there.
            let atStart = gateProjection(exit, lat, lng)
            if atStart.s >= 0 && atStart.s <= CourseBox.slackM && abs(atStart.u) <= exit.halfWidthM {
                open(
                    GateCrossing(direction: .forward, fraction: 0, tMs: tMs, coveredM: cum,
                                 offsetM: atStart.u, gapped: false),
                    fromIdx: i, events: &events
                )
            }
        }
        prevIdx = i
        prevMs = tMs
        prevCum = cum
        sinceAccepted = [(i, here)]
        return events
    }

    /// Ends the stream. A recording that ends in the finish box, or just short
    /// of it, without having crossed into it finishes where its last stretch
    /// there began.
    @discardableResult
    func settle() -> CourseTimingEvent? {
        guard !settled else { return nil }
        settled = true
        guard let tail, !pending.isEmpty,
              let chosen = pick(endCoveredM: tail.cum, endIdx: tail.idx, endMs: tail.ms, gap: tail.gap, endCum: tail.cum)
        else { return nil }
        record(chosen.crossing.tMs, tail.ms)
        pending = []
        return .finished(startMs: chosen.crossing.tMs, endMs: tail.ms)
    }

    // MARK: - The batch rule's helpers

    private func open(_ crossing: GateCrossing, fromIdx: Int, events: inout [CourseTimingEvent]) {
        let wasIdle = pending.isEmpty
        var start = Pending(crossing: crossing, fromIdx: fromIdx, cursor: 0, doneIdx: nil)
        for fix in sinceAccepted where fix.idx >= fromIdx {
            advance(&start, idx: fix.idx, point: fix.point)
        }
        pending.append(start)
        if wasIdle { events.append(.started(atMs: crossing.tMs)) }
    }

    private func advance(_ start: inout Pending, idx: Int, point: CourseBox.Point) {
        if start.doneIdx != nil { return }
        while start.cursor < checkpoints.count {
            let cp = checkpoints[start.cursor]
            guard GateMath.haversineMetres(point.lat, point.lng, cp.lat, cp.lng) <= toleranceM else { break }
            start.cursor += 1
        }
        if start.cursor == checkpoints.count { start.doneIdx = idx }
    }

    private func pick(endCoveredM: Double, endIdx: Int, endMs: Double, gap: FixGap, endCum: Double) -> Pending? {
        pending = pending.filter { endCoveredM - $0.crossing.coveredM <= maxCovered }
        // Pending starts are in time order, so the last valid one is the
        // latest start and so the fastest lap ending here.
        var picked: Pending?
        for s in pending {
            if endCoveredM - s.crossing.coveredM < minCovered { continue }
            if !(endMs > s.crossing.tMs) { continue }
            if gap.gapS > GateConstants.rejectGapS && !plausibleGap(s, gap: gap, endCum: endCum) { continue }
            guard let done = s.doneIdx, done <= endIdx else { continue }
            picked = s
        }
        return picked
    }

    private func record(_ startMs: Double, _ endMs: Double) {
        if let s = bestStartMs, let e = bestEndMs, !(endMs - startMs < e - s) { return }
        bestStartMs = startMs
        bestEndMs = endMs
    }

    /// `_plausibleGap`: at most the finish's longest gap, crossed at about the
    /// runner's own pace since the start.
    private func plausibleGap(_ start: Pending, gap: FixGap, endCum: Double) -> Bool {
        if gap.gapS > CourseBox.finishMaxGapS || gap.fromIdx < 0 { return false }
        let soFarS = (gap.fromMs - start.crossing.tMs) / 1000
        let soFarM = gap.fromCum - start.crossing.coveredM
        guard soFarS > 0, soFarM > 0 else { return false }
        let avg = soFarM / soFarS
        let across = (endCum - gap.fromCum) / gap.gapS
        return across >= CourseBox.gapSpeedMin * avg && across <= CourseBox.gapSpeedMax * avg
    }

    /// `_enteredAcrossGap`: the finish edge entered across a gap the line rule
    /// refuses, timed back from the fix after the gap at the runner's average
    /// pace since the latest pending start.
    private func enteredAcrossGap(
        prev: GateProjection, cur: GateProjection, halfWidthM: Double, fix: GateFix
    ) -> GateCrossing? {
        guard let since = pending.last,
              prev.s < 0 || abs(prev.u) > halfWidthM,
              !(cur.s < 0), !(abs(cur.u) > halfWidthM)
        else { return nil }
        let paceS = (prevMs - since.crossing.tMs) / 1000
        let paceM = prevCum - since.crossing.coveredM
        guard paceS > 0, paceM > 0 else { return nil }
        let backS = cur.s / (paceM / paceS)
        let tMs = max(prevMs, fix.tMs - backS * 1000)
        return GateCrossing(
            direction: .forward,
            fraction: (tMs - prevMs) / (fix.tMs - prevMs),
            tMs: tMs,
            coveredM: max(prevCum, fix.coveredM - cur.s),
            offsetM: cur.u,
            gapped: true
        )
    }
}
