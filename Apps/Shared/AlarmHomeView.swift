// SPDX-License-Identifier: MPL-2.0
#if os(iOS)
import AlarmCore
import SwiftUI
import UIKit
#if os(watchOS)
import WatchKit
#endif

private let beanGreen = Color(red: 0.64, green: 0.87, blue: 0.52)

struct AlarmHomeView: View {
    @Bindable var coordinator: PairCoordinator
    var phoneAlarmsDenied = false
    var permissionError: String?
    var homeAssistant: HomeAssistantBridge?
    @State private var showingSettings = false
    @State private var editingTime = false

    private var hasAlarm: Bool {
        guard let record = coordinator.snapshot.record else { return false }
        return record.blocksNewAlarm || record.phoneScheduled || record.watchScheduled
    }

    private var phoneStopPending: Bool {
        coordinator.role == .phone && coordinator.snapshot.record?.phase == .cancellationPending
    }

    private var showsCountdown: Bool {
        #if os(watchOS)
        return coordinator.snapshot.record?.phase == .armed
        #else
        return !phoneStopPending
        #endif
    }

    private var visibleIssue: String? {
        // Cancellation continues durably, without an alert on the phone's main screen.
        if phoneStopPending { return nil }
        return coordinator.issue ?? (hasAlarm ? coordinator.snapshot.record?.detail : nil)
    }

    private var settings: Binding<AlarmSettings> {
        Binding(get: { coordinator.snapshot.settings.value }, set: { coordinator.updateSettings($0) })
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
                        TimelineView(.everyMinute) { context in
                            let date = hasAlarm ? coordinator.snapshot.record?.occurrence.wakeTime
                                : (try? coordinator.snapshot.settings.value.nextOccurrence(after: context.date).wakeTime)
                            VStack(spacing: 12) {
                                timeDisplay(date)
                                Text(status)
                                    .font(.caption).foregroundStyle(statusColor)
                                    .accessibilityIdentifier("alarm.status")
                                if showsCountdown, let date {
                                    let remaining = RemainingTime(until: date, now: context.date)
                                    Text(remaining.isDue ? "Alarm time reached" : remaining.text)
                                        .font(.footnote).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .accessibilityIdentifier("alarm.remaining")
                                }
                            }
                        }
                        action
                        if let message = visibleIssue {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 20))
                }
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem {
                    #if os(watchOS)
                    if !hasAlarm && !coordinator.busy {
                        Button("Settings", systemImage: "gearshape") { showingSettings = true }
                            .foregroundStyle(.secondary)
                    }
                    #else
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                        .foregroundStyle(.secondary)
                    #endif
                }
            }
            .sheet(isPresented: $showingSettings) {
                AlarmSettingsView(coordinator: coordinator, phoneAlarmsDenied: phoneAlarmsDenied,
                                  permissionError: permissionError, homeAssistant: homeAssistant, locked: hasAlarm || coordinator.busy)
            }
            .onChange(of: hasAlarm) { _, active in
                if active { showingSettings = false }
            }
            #if os(iOS)
            .sheet(isPresented: $editingTime) {
                NavigationStack {
                    DatePicker("Alarm time", selection: wakeBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden().padding()
                        .disabled(hasAlarm || coordinator.busy)
                        .navigationTitle("Alarm time")
                        .toolbar { ToolbarItem { Button("Done") { editingTime = false } } }
                }
                .presentationDetents([.medium])
            }
            #endif
        }
        .tint(beanGreen).preferredColorScheme(.dark)
    }

    @ViewBuilder private func timeDisplay(_ date: Date?) -> some View {
        #if os(watchOS)
        if !hasAlarm && !coordinator.busy {
            WatchTimeEditor(settings: settings)
        } else if let date {
            timeText(date)
        }
        #else
        if let date {
            Button { editingTime = true } label: { timeText(date) }
                .buttonStyle(.plain).disabled(hasAlarm || coordinator.busy)
                .accessibilityLabel("Alarm time")
                .accessibilityValue(date.formatted(date: .omitted, time: .shortened))
                .accessibilityHint(hasAlarm ? "Stop the alarm before editing" : "Double tap to edit")
        }
        #endif
    }

    private func timeText(_ date: Date) -> some View {
        Text(date, format: .dateTime.hour().minute())
            #if os(watchOS)
            .font(.system(size: 48, weight: .medium, design: .rounded))
            #else
            .font(.system(size: 76, weight: .light, design: .rounded))
            #endif
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("alarm.time")
    }

    @ViewBuilder private var action: some View {
        if hasAlarm {
            if !phoneStopPending {
                if coordinator.snapshot.record?.phase == .alerting {
                    stopButton.buttonStyle(.borderedProminent).tint(.red)
                } else {
                    stopButton.buttonStyle(.bordered)
                }
            }
        } else {
            #if os(watchOS)
            Button {
                Task { await coordinator.arm() }
            } label: {
                HStack {
                    if coordinator.busy { ProgressView() }
                    Text(coordinator.busy ? "Arming…" : "Arm")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).disabled(coordinator.busy)
            .accessibilityLabel("Arm both alarms")
            #else
            Text("Arm on Watch").font(.caption).foregroundStyle(.secondary)
            #endif
        }
    }

    private var stopButton: some View {
        Button(role: .destructive) {
            Task { await coordinator.dismissCurrent() }
        } label: {
            Text(coordinator.snapshot.record?.phase == .cancellationPending ? "Retry stop" : "Stop")
                .font(coordinator.snapshot.record?.phase == .alerting ? .title3.weight(.semibold) : .body)
                .frame(maxWidth: .infinity, minHeight: coordinator.snapshot.record?.phase == .alerting ? 48 : nil)
        }
        .disabled(coordinator.busy)
        .accessibilityLabel("Stop both alarms").accessibilityIdentifier("alarm.stop")
    }

    private var status: String {
        guard hasAlarm, let record = coordinator.snapshot.record else {
            return coordinator.busy ? "Arming…" : "Inactive"
        }
        switch record.phase {
        case .preparing: return "Arming…"
        case .armed: return "Active"
        case .alerting: return "Ringing"
        case .cancellationPending: return phoneStopPending ? "Inactive" : "Stop pending"
        case .failed: return "Action needed"
        case .dismissed: return "Inactive"
        }
    }

    private var statusColor: Color {
        guard hasAlarm && !phoneStopPending else { return .secondary }
        switch coordinator.snapshot.record?.phase {
        case .armed, .alerting: return beanGreen
        default: return .orange
        }
    }

    private var wakeBinding: Binding<Date> {
        Binding(get: {
            let value = coordinator.snapshot.settings.value
            return Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                               hour: value.hour, minute: value.minute)) ?? Date()
        }, set: { date in
            guard !hasAlarm && !coordinator.busy else { return }
            var value = coordinator.snapshot.settings.value
            value.hour = Calendar.current.component(.hour, from: date)
            value.minute = Calendar.current.component(.minute, from: date)
            coordinator.updateSettings(value)
        })
    }
}

private struct AlarmSettingsView: View {
    @Bindable var coordinator: PairCoordinator
    var phoneAlarmsDenied: Bool
    var permissionError: String?
    var homeAssistant: HomeAssistantBridge?
    let locked: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Haptic pattern", selection: pattern) {
                        ForEach(AlarmHapticPattern.allCases, id: \.self) { pattern in
                            Text(pattern.title).tag(pattern)
                        }
                    }
                    Stepper(value: setting(\.fallbackMinutes), in: 1...30) {
                        Text("Phone offset: \(coordinator.snapshot.settings.value.fallbackMinutes) min")
                    }
                    Stepper(value: setting(\.hapticSeconds), in: 1...60) {
                        Text("Haptic interval: \(coordinator.snapshot.settings.value.hapticSeconds) sec")
                    }
                }.disabled(locked)
                #if os(iOS)
                if let issue = coordinator.issue ?? coordinator.snapshot.record?.detail {
                    Section("Status") { Text(issue) }
                }
                if phoneAlarmsDenied || permissionError != nil {
                    Section("Phone alarms") {
                        if phoneAlarmsDenied {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                        if let permissionError { Text(permissionError) }
                    }
                }
                Section("About") {
                    Link("Source code · MPL-2.0", destination: URL(string: "https://github.com/agawlbb/alarm-beans")!)
                    Link("Mozilla Public License 2.0", destination: URL(string: "https://mozilla.org/MPL/2.0/")!)
                }
                if let homeAssistant {
                    Section {
                        NavigationLink("Home Assistant") { HomeAssistantSettingsView(bridge: homeAssistant) }
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem { Button("Done") { dismiss() } } }
        }
    }

    private var pattern: Binding<AlarmHapticPattern> {
        Binding(get: { coordinator.snapshot.settings.value.hapticPattern }, set: { pattern in
            guard !locked else { return }
            var settings = coordinator.snapshot.settings.value
            settings.hapticPattern = pattern
            coordinator.updateSettings(settings)
            #if os(watchOS)
            WatchKit.WKInterfaceDevice.current().play(pattern.watchHaptic)
            #endif
        })
    }

    private func setting(_ key: WritableKeyPath<AlarmSettings, Int>) -> Binding<Int> {
        Binding(get: { coordinator.snapshot.settings.value[keyPath: key] }, set: { value in
            guard !locked else { return }
            var settings = coordinator.snapshot.settings.value
            settings[keyPath: key] = value
            coordinator.updateSettings(settings)
        })
    }
}
#endif
