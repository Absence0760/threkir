import SwiftUI
import WidgetKit

/// Today's planned workout on the home screen and the lock screen.
///
/// Lives in the Live Activity's extension rather than one of its own: a
/// `WidgetBundle` holds both, so this costs no second extension target, App
/// ID or App Store profile. What it adds is the App Group it reads the
/// snapshot from (`RunActivity.entitlements`).
///
/// Every word on it is the snapshot's, already localized by Dart; the decode
/// and the choice of what a day shows are `TodayWidgetSnapshot.swift`'s. The
/// one string this file supplies is the brand name on the empty state and in
/// the widget gallery, which is not translated anywhere.
struct TodayWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodayWidget.kind, provider: TodayWorkoutProvider()) { entry in
            TodayWorkoutEntryView(entry: entry)
        }
        .configurationDisplayName(Text(verbatim: "Threkir"))
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct TodayWorkoutEntry: TimelineEntry {
    let date: Date
    let content: TodayWidgetContent
}

/// Reads the snapshot fresh on every request. The app reloads the timeline
/// whenever Dart writes a new one; between writes, the entries at each local
/// midnight are what move the widget to the next day.
struct TodayWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWorkoutEntry {
        TodayWorkoutEntry(date: Date(), content: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWorkoutEntry) -> Void) {
        let now = Date()
        let snapshot = TodayWidgetSnapshot.decode(TodayWidget.storedJSON())
        completion(TodayWorkoutEntry(date: now, content: .of(snapshot, on: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWorkoutEntry>) -> Void) {
        let now = Date()
        guard let snapshot = TodayWidgetSnapshot.decode(TodayWidget.storedJSON()) else {
            // Signed out, or nothing written yet: nothing to roll over, and
            // the app's next write reloads this.
            completion(Timeline(entries: [TodayWorkoutEntry(date: now, content: .empty)], policy: .never))
            return
        }
        let entries = TodayWidget.timelineDates(from: now).map {
            TodayWorkoutEntry(date: $0, content: .of(snapshot, on: $0))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TodayWorkoutEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWorkoutEntry

    var body: some View {
        content
            .widgetURL(entry.content.url)
            .todayWidgetBackground(padded: family == .systemSmall || family == .systemMedium)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            TodayCircularView(content: entry.content)
        case .accessoryRectangular:
            TodayRectangularView(content: entry.content)
        case .accessoryInline:
            TodayInlineView(content: entry.content)
        case .systemMedium:
            TodayMediumView(content: entry.content)
        default:
            TodaySmallView(content: entry.content)
        }
    }
}

extension TodayWidgetContent {
    /// A shape for the state, so a glance reads it before the words do.
    var symbol: String {
        switch kind {
        case .empty, .workout: return "figure.run"
        case .done: return "checkmark.circle.fill"
        case .skipped: return "forward.end.circle"
        case .rest: return "bed.double"
        case .nothingScheduled: return "calendar"
        case .noPlan: return "list.bullet.clipboard"
        case .stale: return "arrow.clockwise"
        }
    }
}

/// The empty state: the app's mark and its name, and a tap opens the app.
private struct TodayBrandView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "figure.run")
                .font(.title2)
                .foregroundStyle(.tint)
            Text(verbatim: "Threkir")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TodaySmallView: View {
    let content: TodayWidgetContent

    var body: some View {
        if content.kind == .empty {
            TodayBrandView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: content.symbol)
                        .foregroundStyle(.tint)
                    Text(content.header)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption)
                Spacer(minLength: 0)
                Text(content.title)
                    .font(.headline)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                TodaySecondaryLine(content: content)
                    .font(.caption)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct TodayMediumView: View {
    let content: TodayWidgetContent

    var body: some View {
        if content.kind == .empty {
            TodayBrandView()
        } else {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: content.symbol)
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                    .frame(width: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.header)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(content.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    TodaySecondaryLine(content: content)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The badge when there is one, otherwise the detail, otherwise nothing.
private struct TodaySecondaryLine: View {
    let content: TodayWidgetContent

    var body: some View {
        if let badge = content.badge {
            Text(badge)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
        } else if !content.detail.isEmpty {
            Text(content.detail)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TodayRectangularView: View {
    let content: TodayWidgetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: content.symbol)
                Text(content.kind == .empty ? "Threkir" : content.header)
                    .lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            if content.kind != .empty {
                Text(content.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                TodaySecondaryLine(content: content)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct TodayInlineView: View {
    let content: TodayWidgetContent

    var body: some View {
        Label(content.kind == .empty ? "Threkir" : content.line, systemImage: content.symbol)
    }
}

private struct TodayCircularView: View {
    let content: TodayWidgetContent

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: content.symbol)
                .font(.title3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.kind == .empty ? "Threkir" : content.line)
    }
}

private extension View {
    /// iOS 17 draws a widget only inside a container background and supplies
    /// the margins itself; iOS 16 does neither, so the system families pad
    /// their own content there.
    @ViewBuilder
    func todayWidgetBackground(padded: Bool) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(.background, for: .widget)
        } else {
            padding(padded ? 16 : 0)
        }
    }
}
