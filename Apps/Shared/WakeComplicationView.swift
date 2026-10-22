// SPDX-License-Identifier: MPL-2.0
#if os(watchOS)
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

struct WakeComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WakeEntry
    // The simulator review host renders the same content outside WidgetKit.
    var previewFamily: WidgetFamily? = nil

    var body: some View {
        content
            .widgetURL(URL(string: "alarmbeans://alarm"))
            .containerBackground(for: .widget) { Color.black }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        switch previewFamily ?? family {
        case .accessoryInline:
            if let time = entry.wakeTime {
                Text(time, format: .dateTime.hour().minute())
            } else {
                Label(entry.label, systemImage: entry.symbol)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                if let time = entry.wakeTime {
                    Text(time, format: .dateTime.hour().minute())
                        .font(.title2.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.65)
                    Text("Alarm armed").font(.caption2)
                } else {
                    Text(entry.label).font(.headline)
                }
            }
        case .accessoryCorner:
            if let time = entry.wakeTime {
                Text(time, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Image(systemName: entry.symbol).font(.title3)
                    .widgetLabel { Text(entry.label) }
            }
        default:
            VStack(spacing: 3) {
                if let time = entry.wakeTime {
                    Text(time, format: .dateTime.hour().minute())
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                } else { Image(systemName: entry.symbol).font(.title3) }
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

#endif
