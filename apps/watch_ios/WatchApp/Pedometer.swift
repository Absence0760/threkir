import Foundation
import CoreMotion

/// Baseline arithmetic for a cumulative step counter, kept apart from
/// `CMPedometer` so it can be exercised without motion hardware — a simulator
/// has none, and neither does a CI runner.
///
/// Mirrors Wear OS's `stepsSinceBaseline`: the first reading becomes the
/// baseline (so the run opens at zero), and a reading below the baseline —
/// which a monotonic counter should never produce — floors at zero rather than
/// publishing "-42 steps" on the summary.
enum PedometerMath {
    struct Reading: Equatable {
        let baseline: Int
        let stepsThisRun: Int
    }

    static func stepsSinceBaseline(currentReading: Int, baseline: Int?) -> Reading {
        let anchor = baseline ?? currentReading
        return Reading(baseline: anchor, stepsThisRun: max(currentReading - anchor, 0))
    }
}

/// Streams steps taken during THIS run from Core Motion.
///
/// `CMPedometer.startUpdates(from:)` is already scoped to a date, but the
/// baseline is applied anyway: the run's start date and the first sample's
/// window are not the same statement, and a platform that ever handed back a
/// device total would otherwise upload a lifetime count as a run's. The
/// baseline is per-`start()`, so a second run opens at a fresh zero.
///
/// An L4 auxiliary effect — it owns nothing the recording stack reads, and
/// every failure mode (no step-counting hardware, a declined Motion & Fitness
/// grant, a handler that only ever reports an error) ends in the caller's count
/// staying nil. Nil is UNMEASURED and the save path omits `metadata.steps`
/// rather than writing 0, which would claim the runner stood still.
final class Pedometer {
    private let pedometer = CMPedometer()
    private var baseline: Int?
    private var updating = false

    func start(from startDate: Date, onUpdate: @escaping (Int) -> Void) {
        guard CMPedometer.isStepCountingAvailable(), !updating else { return }
        updating = true
        baseline = nil
        pedometer.startUpdates(from: startDate) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            let reading = PedometerMath.stepsSinceBaseline(
                currentReading: data.numberOfSteps.intValue,
                baseline: self.baseline
            )
            DispatchQueue.main.async {
                self.baseline = reading.baseline
                onUpdate(reading.stepsThisRun)
            }
        }
    }

    func stop() {
        guard updating else { return }
        updating = false
        pedometer.stopUpdates()
    }
}
