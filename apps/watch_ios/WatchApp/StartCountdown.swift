import Foundation

/// The pre-run 3-2-1 count, as a value.
///
/// Wear OS counts inside its `CountdownOverlay` composable and calls
/// `vm.start()` from the coroutine that finishes it. The arithmetic is lifted
/// out here because the decision it makes — whether this tick is the one that
/// starts recording — is the only part a simulator would be needed to see, and
/// a timer that fires once more than the view expected would otherwise start a
/// second run with nothing able to notice.
struct StartCountdown: Equatable {
    /// Seconds between the Start tap and the run, matching Wear OS.
    static let initialCount = 3

    private(set) var count: Int = StartCountdown.initialCount

    /// Whether the count has run out and `WorkoutManager.start()` is owed.
    var isFinished: Bool { count <= 0 }

    /// One second elapsed. True on the tick that ends the count, false on
    /// every other — including any tick after it has already ended, so a
    /// late or duplicated timer fire cannot start a run twice.
    @discardableResult
    mutating func tick() -> Bool {
        guard count > 0 else { return false }
        count -= 1
        return count == 0
    }
}
