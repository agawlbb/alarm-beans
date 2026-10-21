// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import SwiftUI

private let beanGreen = Color(red: 0.64, green: 0.87, blue: 0.52)

struct AlarmHomeView: View {
    @Bindable var coordinator: PairCoordinator
    var authorize: (() async throws -> Void)?
    @State private var showingSettings = false
    @State private var showingSetup = false
    @State private var permissionMessage: String?

    private var hasAlarm: Bool {
        guard let record = coordinator.snapshot.record else { return false }
        return record.blocksNewAlarm || record.phoneScheduled || record.watchScheduled
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if coordinator.role == .phone || !hasAlarm { header }
                    if hasAlarm, let record = coordinator.snapshot.record {
                        activeAlarm(record)
                    } else {
                        editor
                    }
                    if let issue = coordinator.issue {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    #if os(iOS)
                    Button("Setup & alarm permission", systemImage: "checkmark.shield") { showingSetup = true }
                        .font(.subheadline)
                    #endif
                    NavigationLink("About Alarm Beans") { AboutView() }
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black)
            .navigationTitle("Alarm Beans")
            .toolbar {
                ToolbarItem {
                    Button("Settings", systemImage: "slider.horizontal.3") { showingSettings = true }
                        .disabled(hasAlarm || coordinator.busy)
                }
            }
            .sheet(isPresented: $showingSettings) {
                AlarmSettingsView(coordinator: coordinator)
            }
            .sheet(isPresented: $showingSetup) { setup }
        }
        .tint(beanGreen)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        #if os(watchOS)
        Text("A quieter morning.").font(.headline)
        #else
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "leaf.fill").font(.title).foregroundStyle(beanGreen).accessibilityHidden(true)
            Text(hasAlarm ? "Rest easy." : "A quieter morning.")
                .font(.title2.weight(.semibold))
            Text("A gentle tap first. A sound if you need it.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        #endif
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            DatePicker("Wake time", selection: wakeBinding, displayedComponents: .hourAndMinute)
                .disabled(coordinator.busy)
                #if os(iOS)
                .datePickerStyle(.wheel)
                #endif
            #if os(watchOS)
            Button {
                Task { await coordinator.arm() }
            } label: {
                HStack {
                    if coordinator.busy { ProgressView() }
                    Text(coordinator.busy ? "Arming both…" : "Arm both alarms")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).disabled(coordinator.busy)
            Text("Keep this app open until Armed appears.").font(.caption2).foregroundStyle(.secondary)
            #endif
            if let occurrence = try? coordinator.snapshot.settings.value.nextOccurrence(after: Date()) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        AlarmTimeView(title: "Silent Watch wake-up", date: occurrence.wakeTime, now: context.date,
                                      icon: "applewatch.radiowaves.left.and.right", dueText: "Wake time reached")
                        AlarmTimeView(title: "Audible iPhone fallback", date: occurrence.fallbackTime, now: context.date,
                                      icon: "speaker.wave.2", dueText: "Fallback time reached")
                    }
                }
            }
            #if os(iOS)
            Label("Open Alarm Beans on your Watch and tap Arm both alarms.", systemImage: "applewatch")
                .font(.subheadline).foregroundStyle(beanGreen)
            #endif
        }
    }

    private func activeAlarm(_ record: AlarmRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(statusTitle(record), systemImage: statusIcon(record))
                .font(.headline).foregroundStyle(record.phase == .armed ? beanGreen : .orange)
                .accessibilityIdentifier("alarm.status")
            #if os(watchOS)
            stopButton(record)
            #endif
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 14) {
                    AlarmTimeView(title: "Silent Watch wake-up", date: record.occurrence.wakeTime, now: context.date,
                                  icon: "applewatch.radiowaves.left.and.right", dueText: "Wake time reached")
                    AlarmTimeView(title: "Audible iPhone fallback", date: record.occurrence.fallbackTime, now: context.date,
                                  icon: "speaker.wave.2", dueText: "Fallback time reached")
                }
            }
            if let detail = record.detail { Text(detail).font(.footnote).foregroundStyle(.orange) }
            #if os(iOS)
            stopButton(record)
            #endif
        }
    }

    private func stopButton(_ record: AlarmRecord) -> some View {
        Button(role: .destructive) {
            Task { await coordinator.dismissCurrent() }
        } label: {
            Label(record.phase == .cancellationPending ? "Retry cancellation" : "Stop both alarms", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(coordinator.busy)
        .accessibilityIdentifier("alarm.stop")
    }

    private func statusTitle(_ record: AlarmRecord) -> String {
        switch record.phase {
        case .preparing: "Arming both alarms…"
        case .armed: "Armed"
        case .alerting: "Time to wake up"
        case .cancellationPending: "Cancellation pending"
        case .failed: "Action needed"
        case .dismissed: "Not armed"
        }
    }

    private func statusIcon(_ record: AlarmRecord) -> String {
        record.phase == .armed ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var wakeBinding: Binding<Date> {
        Binding(get: {
            let settings = coordinator.snapshot.settings.value
            return Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                               hour: settings.hour, minute: settings.minute)) ?? Date()
        }, set: { date in
            var settings = coordinator.snapshot.settings.value
            settings.hour = Calendar.current.component(.hour, from: date)
            settings.minute = Calendar.current.component(.minute, from: date)
            coordinator.updateSettings(settings)
        })
    }

    private var setup: some View {
        NavigationStack {
            List {
                Section("One-time setup") {
                    Text("Install Alarm Beans on both devices. Allow iPhone alarms, then choose your wake time and arm from the Watch.")
                    Text("Wear and charge your Watch, enable haptics, and keep your paired iPhone reachable for cancellation.")
                    Text("Add the Alarm Beans complication using your Watch face editor. It shows a time only after both alarms are armed.")
                }
                if let authorize {
                    Button("Allow iPhone alarms") {
                        Task {
                            do { try await authorize(); permissionMessage = "iPhone alarms are allowed." }
                            catch { permissionMessage = error.localizedDescription }
                        }
                    }
                }
                if let permissionMessage { Text(permissionMessage) }
            }
            .navigationTitle("Setup")
            .toolbar { ToolbarItem { Button("Done") { showingSetup = false } } }
        }
    }
}

private struct AlarmTimeView: View {
    let title: String
    let date: Date
    let now: Date
    let icon: String
    let dueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(date, format: .dateTime.hour().minute())
                .font(.title2.weight(.semibold)).monospacedDigit()
            Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.caption).foregroundStyle(.secondary)
            Text(RemainingTime(until: date, now: now).isDue ? dueText : RemainingTime(until: date, now: now).text)
                .font(.footnote).foregroundStyle(beanGreen)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AlarmSettingsView: View {
    @Bindable var coordinator: PairCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: setting(\.fallbackMinutes), in: 1...30) {
                    Text("Audible fallback: \(coordinator.snapshot.settings.value.fallbackMinutes) min later")
                }
                Stepper(value: setting(\.hapticSeconds), in: 1...60) {
                    Text("Watch taps every \(coordinator.snapshot.settings.value.hapticSeconds) sec")
                }
                Text("Settings are remembered for your next wake-up. Arm both alarms on your Watch.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Timing")
            .toolbar { ToolbarItem { Button("Done") { dismiss() } } }
        }
    }

    private func setting(_ key: WritableKeyPath<AlarmSettings, Int>) -> Binding<Int> {
        Binding(get: { coordinator.snapshot.settings.value[keyPath: key] }, set: { value in
            var settings = coordinator.snapshot.settings.value
            settings[keyPath: key] = value
            coordinator.updateSettings(settings)
        })
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Text("Alarm Beans").font(.headline)
            Text("A quieter wake-up, with an audible backup.")
            Text("Early beta. Verify alarm behavior on your own paired devices before relying on it overnight.")
                .font(.footnote)
            Link("Source code · MPL-2.0", destination: URL(string: "https://github.com/agawlbb/alarm-beans")!)
            Link("Mozilla Public License 2.0", destination: URL(string: "https://mozilla.org/MPL/2.0/")!)
        }
        .navigationTitle("About")
    }
}
