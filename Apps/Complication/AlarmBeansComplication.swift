// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import SwiftUI
import WidgetKit

struct WakeEntry: TimelineEntry {
    let date: Date
    let record: AlarmRecord?
    let storageFailed: Bool

    var wakeTime: Date? { record?.complicationTime(at: date) }
    var needsAttention: Bool {
        storageFailed || record?.phase == .cancellationPending ||
            (record?.phoneScheduled == true && wakeTime == nil)
    }
    var label: String { needsAttention ? "Check app" : "No alarm" }
    var symbol: String {
        if wakeTime != nil { return "alarm.fill" }
        return needsAttention ? "exclamationmark.circle" : "alarm"
    }
}

struct WakeProvider: TimelineProvider {
    func placeholder(in context: Context) -> WakeEntry {
        WakeEntry(date: Date(), record: nil, storageFailed: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WakeEntry) -> Void) {
        Task { @MainActor in completion(readEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WakeEntry>) -> Void) {
        Task { @MainActor in
            let current = readEntry()
            var entries = [current]
            if let record = current.record {
                for date in [record.occurrence.wakeTime, record.occurrence.watchExpiry] where date > current.date {
                    entries.append(WakeEntry(date: date, record: record, storageFailed: false))
                }
            }
            // The expiry entry removes old times without relying on a new process launch.
            completion(Timeline(entries: entries.sorted { $0.date < $1.date }, policy: .never))
        }
    }

    @MainActor private func readEntry() -> WakeEntry {
        do {
            let snapshot = try AlarmStore().load()
            return WakeEntry(date: Date(), record: snapshot.record, storageFailed: false)
        } catch {
            return WakeEntry(date: Date(), record: nil, storageFailed: true)
        }
    }
}

struct WakeComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WakeEntry

    var body: some View {
        content
            .widgetURL(URL(string: "alarmbeans://alarm"))
            .containerBackground(for: .widget) { Color.black }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            if let time = entry.wakeTime {
                Label {
                    Text(time, format: .dateTime.hour().minute())
                } icon: { Image(systemName: entry.symbol) }
            } else {
                Label(entry.label, systemImage: entry.symbol)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Label("Alarm Beans", systemImage: entry.symbol).font(.caption)
                if let time = entry.wakeTime {
                    Text(time, format: .dateTime.hour().minute())
                        .font(.title2.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.65)
                    Text(time <= entry.date ? "Wake-up active" : "Silent wake-up").font(.caption2)
                } else {
                    Text(entry.label).font(.headline)
                }
            }
        case .accessoryCorner:
            Image(systemName: entry.symbol)
                .font(.title3)
                .widgetLabel {
                    if let time = entry.wakeTime { Text(time, format: .dateTime.hour().minute()) }
                    else { Text(entry.label) }
                }
        default:
            VStack(spacing: 3) {
                Image(systemName: entry.symbol).font(.caption)
                if let time = entry.wakeTime {
                    Text(time, format: .dateTime.hour().minute())
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var accessibilityText: String {
        if let time = entry.wakeTime {
            return "Alarm Beans, active wake-up at \(time.formatted(date: .omitted, time: .shortened)). Open to view or dismiss."
        }
        return "Alarm Beans, \(entry.label). Open to set or view your alarm."
    }
}

@main struct AlarmBeansComplication: Widget {
    let kind = "AlarmBeansWakeTime"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WakeProvider()) { WakeComplicationView(entry: $0) }
            .configurationDisplayName("Alarm Beans")
            .description("Your active silent wake-up time. Tap to set, view, or dismiss your alarm.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

