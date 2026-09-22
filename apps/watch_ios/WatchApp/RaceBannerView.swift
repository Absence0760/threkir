import SwiftUI

/// The pre-run live-race banner: which of Arm / Go the race is in, whose
/// race it is, and what the runner does next.
///
/// Pre-run only, mirroring Wear OS's placement — "wait for GO" and "tap
/// Start" are both instructions for a runner who has not started yet, and a
/// wrist mid-run has nothing to spend the line on. `RaceBanner` owns the
/// decision to show it at all; this view only renders it.
struct RaceBannerView: View {
    let race: LiveRace?

    var body: some View {
        if let phase = RaceBanner.phase(for: race) {
            VStack(alignment: .leading, spacing: 2) {
                switch phase {
                case .armed:
                    Text("RACE ARMED")
                        .font(.caption2)
                        .foregroundColor(AppTheme.coral)
                case .live:
                    Text("RACE LIVE")
                        .font(.caption2)
                        .foregroundColor(AppTheme.coral)
                }

                if let title = RaceBanner.title(for: race) {
                    Text(verbatim: title)
                        .font(.caption)
                        .foregroundColor(AppTheme.parchment)
                } else {
                    Text("Event")
                        .font(.caption)
                        .foregroundColor(AppTheme.parchment)
                }

                switch phase {
                case .armed:
                    Text("Wait for GO")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                case .live:
                    Text("Tap Start")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Three stacked captions are one fact, not three: VoiceOver
            // reading them as separate elements makes the runner swipe
            // through a status line.
            .accessibilityElement(children: .combine)
        }
    }
}
