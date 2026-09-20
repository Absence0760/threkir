import Foundation
import HealthKit

/// What the runner is about to do, as the pre-run picker offers it.
///
/// Two things hang off the choice and they are not the same thing. The stored
/// token is what `runs.activity_type` admits — the `runs_activity_type_check`
/// vocabulary, which `ActivityTypeVocabularyTests` reads out of the migration
/// rather than restating — and the `HKWorkoutActivityType` is what makes
/// HealthKit's own energy and heart-rate semantics right for a walk or a ride.
/// Stamping the row without configuring the session would leave Health
/// scoring a bike ride as a run.
///
/// The picker offers four of the five values the column admits, the same four
/// Wear OS's chip cycles; `ActivityTypeVocabularyTests` holds that omission to
/// a declared reason so a widened CHECK cannot pass unnoticed.
enum RunActivityType: String, CaseIterable {
    case run
    case walk
    case hike
    case cycle

    /// The next value the picker cycles to, wrapping. Same order as Wear OS's
    /// chip so a runner with both wrists learns one sequence.
    var next: RunActivityType {
        let all = RunActivityType.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// The product's word for this activity, which is the phone's and the
    /// web's verbatim in every locale (decisions § 713 / § 1155).
    ///
    /// The keys are namespaced rather than being the English word itself:
    /// `"Run"` is already a catalog key — the complication's idle label,
    /// translated "Lauf" / "Correr" / "ラン" — and those are exactly the
    /// abbreviated wrist forms § 713 removed from the activity vocabulary.
    /// One English word, two meanings, two translations.
    var label: String {
        switch self {
        case .run: return String(localized: "activityType.run")
        case .walk: return String(localized: "activityType.walk")
        case .hike: return String(localized: "activityType.hike")
        case .cycle: return String(localized: "activityType.cycle")
        }
    }

    /// How HealthKit should score the workout.
    ///
    /// `hike` maps to running, not to `.hiking`: the product's word for the
    /// value is "Trail run" everywhere it is shown, so someone who picks it is
    /// running, and filing it in Health as a hike would report a runner's
    /// energy expenditure as a walker's. The finer classification lives on our
    /// own row, which is the only place it exists.
    var healthKitActivityType: HKWorkoutActivityType {
        switch self {
        case .run, .hike: return .running
        case .walk: return .walking
        case .cycle: return .cycling
        }
    }

    /// A token from a checkpoint or another build, or `.run` when it is one
    /// this build does not know.
    ///
    /// Fails closed to the value the column defaults to rather than dropping
    /// the recovery: an unknown token means this build is older than whatever
    /// wrote it, and a recovered run is worth more than its classification.
    static func parse(_ raw: String?) -> RunActivityType {
        guard let raw, let known = RunActivityType(rawValue: raw) else { return .run }
        return known
    }
}
