import Foundation

/// The three settings the phone hands this wrist beyond the unit and the cue
/// switch, and what each one does here. None of them has an editor on the
/// watch: the phone and web own them, and they arrive over the application
/// context `PhonePreferences` decodes.
///
/// Each is stored the moment it arrives, because the context lands while the
/// app is backgrounded and the recorder reads it minutes or hours later — at
/// `start()`, at a checkpoint, at `stop()` — with no phone in range. Every
/// reader fails closed: a value this build cannot read is no value, never a
/// guess.

/// `default_activity_type` — the activity the pre-run picker opens on.
enum DefaultActivityType {
    static let storageKey = "default_activity_type"

    /// One of the four the picker cycles. The column's fifth value, `stroller`,
    /// is not something this wrist can record as, so it decodes as nothing and
    /// the picker keeps the activity it already shows.
    static func decode(_ raw: Any?) -> RunActivityType? {
        guard let token = raw as? String else { return nil }
        return RunActivityType(rawValue: token)
    }

    static func stored(in defaults: UserDefaults = .standard) -> RunActivityType? {
        decode(defaults.string(forKey: storageKey))
    }

    static func save(_ type: RunActivityType, in defaults: UserDefaults = .standard) {
        defaults.set(type.rawValue, forKey: storageKey)
    }

    /// What the picker shows once a new default arrives. A default primes the
    /// picker and never overrides the runner: not mid-run, and not after they
    /// have picked on the wrist themselves. Wear OS's `applyUniversalPrefsAsync`
    /// makes the same two exceptions.
    static func primed(
        current: RunActivityType,
        default preferred: RunActivityType,
        isIdle: Bool,
        pickedOnWrist: Bool
    ) -> RunActivityType {
        isIdle && !pickedOnWrist ? preferred : current
    }
}

/// `privacy_default` — the visibility a run recorded here is saved with.
enum PrivacyDefault {
    static let storageKey = "privacy_default"
    static let accepted: Set<String> = ["public", "followers", "private"]

    static func decode(_ raw: Any?) -> String? {
        guard let value = raw as? String, accepted.contains(value) else { return nil }
        return value
    }

    static func stored(in defaults: UserDefaults = .standard) -> String? {
        decode(defaults.string(forKey: storageKey))
    }

    static func save(_ value: String, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: storageKey)
    }

    /// The `runs.is_public` snapshot a finished run carries: `public` is true,
    /// `followers` and `private` are false, and nil — the phone never said —
    /// stays nil so the key is omitted and the column's private default holds.
    /// `runs.is_public` is a boolean; the followers nuance lives in the phone
    /// and web social layer, exactly as on Wear OS
    /// (`isPublicFromPrivacyDefault`).
    static func isPublic(_ privacyDefault: String?) -> Bool? {
        privacyDefault.map { $0 == "public" }
    }
}

/// `hr_zone_cutoffs` — the ladder the live heart-rate reading is badged
/// against. The phone resolves it from `hr_zones` > `max_hr_bpm` > Tanaka off
/// `date_of_birth` (`AppleWatchPrefsBridge.zoneCutoffsForWatch`), so the
/// runner's date of birth never reaches this device: five numbers are all the
/// badge needs.
enum HeartRateZones {
    static let storageKey = "hr_zone_cutoffs"
    static let boundRange = 40...240

    /// Five strictly-ascending upper bounds (Z1...Z5) inside `boundRange`, or
    /// an empty ladder — the phone's word for "this runner has no zones", which
    /// clears the badge. Anything else is not a ladder and decodes as nil,
    /// which the caller reads as "keep what you have". The gate is Wear OS's
    /// `parseHrZones`, so a ladder that would badge on one wrist badges on the
    /// other.
    static func decode(_ raw: Any?) -> [Int]? {
        guard let bounds = raw as? [Int] else { return nil }
        if bounds.isEmpty { return [] }
        guard bounds.count == 5,
              bounds.allSatisfy(boundRange.contains),
              zip(bounds, bounds.dropFirst()).allSatisfy({ $0 < $1 })
        else { return nil }
        return bounds
    }

    static func stored(in defaults: UserDefaults = .standard) -> [Int] {
        decode(defaults.array(forKey: storageKey)) ?? []
    }

    static func save(_ cutoffs: [Int], in defaults: UserDefaults = .standard) {
        defaults.set(cutoffs, forKey: storageKey)
    }

    /// The 1...5 zone a reading falls in, or nil when there is no ladder — no
    /// badge rather than a stranger's zones. A reading at a bound belongs to
    /// the zone that bound closes; anything above Z4's bound is Z5. The twin of
    /// Wear OS's `hrZoneOf`.
    static func zone(bpm: Int, cutoffs: [Int]) -> Int? {
        guard cutoffs.count == 5 else { return nil }
        for (index, bound) in cutoffs.prefix(4).enumerated() where bpm <= bound {
            return index + 1
        }
        return 5
    }
}
