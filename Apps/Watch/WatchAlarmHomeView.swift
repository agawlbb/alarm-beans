// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import SwiftUI

struct WatchAlarmHomeView: View {
    @Bindable var coordinator: PairCoordinator
    @State private var showingSettings = false
    private let green = Color(red: 0.64, green: 0.87, blue: 0.52)

    private var hasAlarm: Bool {
        guard let record = coordinator.snapshot.record else { return false }
        return record.blocksNewAlarm || record.phoneScheduled || record.watchScheduled
    }

    private var settings: Binding<AlarmSettings> {
        Binding(get: { coordinator.snapshot.settings.value }, set: { coordinator.updateSettings($0) })
    }

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if hasAlarm, let record = coordinator.snapshot.record {
                Text(record.occurrence.wakeTime, format: .dateTime.hour().minute())
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(status(record.phase)).font(.caption)
                    .foregroundStyle(record.phase == .armed || record.phase == .alerting ? green : .orange)
                if record.phase == .armed {
                    TimelineView(.everyMinute) { context in
                        Text(RemainingTime(until: record.occurrence.wakeTime, now: context.date).text)
                            .font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                WatchTimeEditor(settings: settings).disabled(coordinator.busy)
                Text(coordinator.busy ? "Arming…" : "Inactive")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if hasAlarm {
                Button(role: .destructive) { Task { await coordinator.dismissCurrent() } } label: {
                    Text("Stop").font(.headline).frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(coordinator.busy).accessibilityIdentifier("alarm.stop")
            } else {
                HStack(spacing: 8) {
                    Button { Task { await coordinator.arm() } } label: {
                        Group {
                            if coordinator.busy { ProgressView() }
                            else { Text("Arm").font(.headline) }
                        }.frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent).tint(green)
                    .disabled(coordinator.busy).accessibilityLabel("Arm both alarms")
                    if !coordinator.busy {
                        Button { showingSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18, weight: .regular))
                                .frame(width: 40, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Settings").accessibilityIdentifier("alarm.settings")
                    }
                }
            }
            if let issue = coordinator.issue {
                Text(issue).font(.caption2).foregroundStyle(.orange)
                    .lineLimit(3).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
        .background(Color.black)
        .sheet(isPresented: $showingSettings) { WatchAlarmSettingsView(coordinator: coordinator) }
        .onChange(of: hasAlarm) { _, active in if active { showingSettings = false } }
        .tint(green).preferredColorScheme(.dark)
    }

    private func status(_ phase: AlarmPhase) -> String {
        switch phase {
        case .preparing: "Arming…"
        case .armed: "Active"
        case .alerting: "Ringing"
        case .cancellationPending: "Stop pending"
        case .failed: "Action needed"
        case .dismissed: "Inactive"
        }
    }
}
