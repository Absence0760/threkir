import Foundation

/// A lap the runner marked, held as the CUMULATIVE position of the mark.
///
/// Cumulative rather than split because a mark is an event at a point in the
/// run: the split it opens is not known until the next mark or the stop. It is
/// also what rides in the crash checkpoint, where the run is by definition
/// unfinished and the trailing split does not exist yet.
struct LapMark: Codable, Equatable {
    let index: Int
    let atSeconds: Double
    let distanceMetres: Double
}

/// One split row, in the `runs.metadata.laps` shape `docs/backend/metadata.md`
/// registers: per-lap deltas, with `start_offset_s` the cumulative duration up
/// to the START of the lap (so the first lap is 0).
struct RunLap: Equatable {
    let index: Int
    let startOffsetSeconds: Int
    let distanceMetres: Double
    let durationSeconds: Int
}

enum RunLaps {
    /// Turn the cumulative marks into the registered split rows.
    ///
    /// The trailing row covers the partial between the last mark and the stop,
    /// and is emitted only when it is non-trivial (>= 1 s and >= 1 m) so a
    /// lap-then-stop does not land a phantom 0/0 lap. Mirrors Wear OS's
    /// `buildFinishedLapsList` — the same run marked on either wrist has to
    /// produce the same rows, because one phone reads both.
    static func splits(
        marks: [LapMark],
        totalDistanceMetres: Double,
        totalDurationSeconds: Int
    ) -> [RunLap] {
        guard !marks.isEmpty else { return [] }
        var out: [RunLap] = []
        var prevSeconds = 0
        var prevDistance: Double = 0
        for mark in marks {
            let atSeconds = Int(mark.atSeconds)
            out.append(RunLap(
                index: mark.index,
                startOffsetSeconds: prevSeconds,
                distanceMetres: max(mark.distanceMetres - prevDistance, 0),
                durationSeconds: max(atSeconds - prevSeconds, 0)
            ))
            prevSeconds = atSeconds
            prevDistance = mark.distanceMetres
        }
        let finalSeconds = totalDurationSeconds - prevSeconds
        let finalDistance = totalDistanceMetres - prevDistance
        if finalSeconds >= 1 && finalDistance >= 1 {
            out.append(RunLap(
                index: out.count + 1,
                startOffsetSeconds: prevSeconds,
                distanceMetres: finalDistance,
                durationSeconds: finalSeconds
            ))
        }
        return out
    }

    /// The value for the `laps` key of the run hand-off envelope.
    ///
    /// Property-list types only: `WCSession.transferFile(_:metadata:)` refuses
    /// metadata that is not a plist, so a struct encoded here would cost the
    /// whole run rather than its laps.
    static func envelopeValue(_ laps: [RunLap]) -> [[String: Any]] {
        laps.map { lap in
            [
                "index": lap.index,
                "start_offset_s": lap.startOffsetSeconds,
                "distance_m": lap.distanceMetres,
                "duration_s": lap.durationSeconds,
            ]
        }
    }
}
