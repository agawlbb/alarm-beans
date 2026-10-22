// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import SwiftUI
import WidgetKit

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

@main struct AlarmBeansComplication: Widget {
    let kind = "AlarmBeansWakeTime"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WakeProvider()) { WakeComplicationView(entry: $0) }
            .configurationDisplayName("Alarm Beans")
            .description("Your active silent wake-up time. Tap to set, view, or dismiss your alarm.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

