import ActivityKit
import SwiftUI
import WidgetKit

/// The lock-screen and Dynamic Island presentation of an in-progress run.
///
/// Every string on screen arrives already localized and unit-formatted in
/// `RunActivityAttributes.ContentState`; nothing here formats or translates,
/// which is why this extension carries no String Catalog. The one value it
/// renders itself is the clock, and only because `Text(_:style:.timer)` ticks
/// on-device: the alternative is an ActivityKit update per second for the
/// length of an ultra.
@main
struct RunActivityBundle: WidgetBundle {
    var body: some Widget {
        RunActivityWidget()
    }
}

struct RunActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            RunActivityLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RunActivityStat(
                        label: context.state.distanceLabel,
                        value: context.state.distanceText
                    )
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RunActivityStat(
                        label: context.state.paceLabel,
                        value: context.state.paceText,
                        alignment: .trailing
                    )
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RunActivityStat(
                        label: context.state.timeLabel,
                        value: nil,
                        alignment: .center
                    ) {
                        RunActivityClock(state: context.state)
                            .font(.system(.title, design: .rounded).monospacedDigit())
                    }
                }
            } compactLeading: {
                RunActivityGlyph(paused: context.state.paused)
            } compactTrailing: {
                RunActivityClock(state: context.state)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 56)
                    .accessibilityLabel(context.state.title)
            } minimal: {
                RunActivityGlyph(paused: context.state.paused)
            }
        }
    }
}

/// `figure.run` while the run is live, `pause.fill` while it is held — the
/// compact and minimal presentations are a few points wide, so the pause
/// state has to survive as a shape rather than as the word the header uses.
struct RunActivityGlyph: View {
    let paused: Bool

    var body: some View {
        Image(systemName: paused ? "pause.fill" : "figure.run")
            .foregroundStyle(.tint)
    }
}

/// The run clock. Live runs get a system timer counting up from the anchor
/// date, which ticks with no further updates; a paused run gets the frozen
/// string the app formatted, because a timer that kept running while the
/// runner stood still would be the one number on this surface that lies.
struct RunActivityClock: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if state.paused {
            Text(state.elapsedText)
        } else {
            Text(state.timerStart, style: .timer)
        }
    }
}

/// One labelled stat. `value` renders as text; pass `content` instead for a
/// stat whose value is a view, which is what the clock needs.
struct RunActivityStat<Content: View>: View {
    let label: String
    let value: String?
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let value {
                Text(value)
                    .font(.system(.title3, design: .rounded).monospacedDigit())
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .accessibilityElement(children: .combine)
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .trailing: return .trailing
        case .center: return .center
        default: return .leading
        }
    }
}

extension RunActivityStat where Content == EmptyView {
    init(label: String, value: String, alignment: HorizontalAlignment = .leading) {
        self.init(label: label, value: value, alignment: alignment) { EmptyView() }
    }
}

struct RunActivityLockScreenView: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                RunActivityStat(label: state.timeLabel, value: nil) {
                    RunActivityClock(state: state)
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                }
                RunActivityStat(label: state.distanceLabel, value: state.distanceText)
                RunActivityStat(
                    label: state.paceLabel,
                    value: state.paceText,
                    alignment: .trailing
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
