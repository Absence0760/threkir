// Active-run complication for watchOS 10+. Renders the live workout
// stats (elapsed time, distance, current pace) on the runner's watch
// face.
//
// This runs in the `WatchAppComplication` extension, a separate PROCESS
// from the app that owns the HKWorkoutSession — it cannot reach
// `WorkoutManager` and never tries. Everything it draws comes from the
// snapshot the host writes to the App Group through `ActiveRunBridge`.
// README.md in this directory describes the target.
//
// The entry shaping and the formatting live in `ActiveRunTimeline.swift`
// and `WatchApp/RunFormat.swift`, both members of this target AND of
// `WatchApp`, which is what lets `WatchAppTests` cover them. This file
// holds what cannot be shared: the `@main` bundle and the views.
//
// The `accessoryCircular`, `accessoryCorner`, `accessoryRectangular`,
// and `accessoryInline` families cover Modular, Infograph, X-Large,
// and most other watch faces. Each family gets its own variant so a
// runner who picks the X-Large face sees the full stat trio while
// the Infograph corner just shows pace.

import SwiftUI
import WidgetKit

// MARK: - Provider

/// Hands the system fresh entries on a coarse cadence; the schedule itself
/// is `ActiveRunTimeline`'s. The Run app explicitly reloads the timeline on
/// workout state transitions (start, pause, resume, stop) via
/// `WidgetCenter.shared.reloadTimelines(...)`.
struct ActiveRunProvider: TimelineProvider {
    typealias Entry = ActiveRunEntry

    func placeholder(in context: Context) -> Entry {
        ActiveRunEntry(
            date: .now,
            isActive: false,
            elapsedSeconds: 0,
            distanceMeters: 0,
            paceSecPerKm: nil,
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(ActiveRunTimeline.entry(from: ActiveRunBridge.read(), now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entries = ActiveRunTimeline.entries(from: ActiveRunBridge.read(), now: .now)
        // Idle — one static entry and no schedule; the app calls
        // reloadTimelines on the next state change so we don't have to
        // budget refreshes for a watch face that isn't going to change.
        let policy: TimelineReloadPolicy = entries.first?.isActive == true ? .atEnd : .never
        completion(Timeline(entries: entries, policy: policy))
    }
}

// MARK: - Views

/// One entry view; SwiftUI's `widgetFamily` environment value picks
/// the right rendering. Keeping all variants in one file makes it
/// trivial to keep them visually consistent (same accent colour,
/// same number formatting, same fall-back state).
struct ActiveRunEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ActiveRunEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(entry: entry)
        case .accessoryCorner:
            CornerView(entry: entry)
        case .accessoryInline:
            InlineView(entry: entry)
        case .accessoryRectangular:
            RectangularView(entry: entry)
        @unknown default:
            CircularView(entry: entry)
        }
    }
}

private struct CircularView: View {
    let entry: ActiveRunEntry

    var body: some View {
        if entry.isActive {
            VStack(spacing: 0) {
                Text("RUN")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tint)
                Text(formatPaceSecPerKm(entry.paceSecPerKm))
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        } else {
            VStack(spacing: 0) {
                Image(systemName: "figure.run")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Text("Start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CornerView: View {
    let entry: ActiveRunEntry

    var body: some View {
        if entry.isActive {
            Text(formatPaceSecPerKm(entry.paceSecPerKm))
                .font(.body.weight(.semibold))
                .widgetCurvesContent()
                .widgetLabel("Pace")
        } else {
            Image(systemName: "figure.run")
                .widgetLabel("Run")
        }
    }
}

private struct InlineView: View {
    let entry: ActiveRunEntry

    var body: some View {
        if entry.isActive {
            Label(ActiveRunTimeline.statLine(entry), systemImage: "figure.run")
        } else {
            Label("Tap to start", systemImage: "figure.run")
        }
    }
}

private struct RectangularView: View {
    let entry: ActiveRunEntry

    var body: some View {
        if entry.isActive {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.run").font(.caption2)
                    Text("RUNNING")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text(formatElapsed(entry.elapsedSeconds))
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(ActiveRunTimeline.statLine(entry))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.run").font(.caption2)
                    Text("RUN ONWARD")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text("Tap to start")
                    .font(.body.weight(.medium))
                Text("Open the Run app")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget

@main
struct ActiveRunComplicationBundle: WidgetBundle {
    var body: some Widget {
        ActiveRunComplication()
    }
}

struct ActiveRunComplication: Widget {
    /// One constant, read by both targets — see `ActiveRunBridge`. The host
    /// app's `reloadTimelines(ofKind:)` must name exactly this, and a kind no
    /// widget declares is a silent no-op there.
    let kind: String = ActiveRunBridge.complicationKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveRunProvider()) { entry in
            ActiveRunEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Active Run")
        .description("Live pace, distance, and elapsed time during a run.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}
