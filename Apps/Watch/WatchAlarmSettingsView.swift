// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import SwiftUI
import WatchKit

enum WatchSettingsScreen: Hashable { case pattern, interval, offset }

struct WatchAlarmSettingsView: View {
    @Bindable var coordinator: PairCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var path: [WatchSettingsScreen]

    init(coordinator: PairCoordinator, initialPath: [WatchSettingsScreen] = []) {
        self.coordinator = coordinator
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                NavigationLink(value: WatchSettingsScreen.pattern) {
                    row("Haptic pattern", value: coordinator.snapshot.settings.value.hapticPattern.title)
                }
                NavigationLink(value: WatchSettingsScreen.interval) {
                    row("Haptic interval", value: "\(coordinator.snapshot.settings.value.hapticSeconds) sec")
                }
                NavigationLink(value: WatchSettingsScreen.offset) {
                    row("Phone offset", value: "\(coordinator.snapshot.settings.value.fallbackMinutes) min")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem { Button("Done") { dismiss() }.buttonStyle(.plain) } }
            .navigationDestination(for: WatchSettingsScreen.self) { screen in
                switch screen {
                case .pattern: patterns
                case .interval: numbers(title: "Interval", range: 1...60, unit: "sec", key: \.hapticSeconds)
                case .offset: numbers(title: "Phone offset", range: 1...30, unit: "min", key: \.fallbackMinutes)
                }
            }
        }
        .font(.body).preferredColorScheme(.dark)
    }

    private func row(_ name: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var patterns: some View {
        List {
            ForEach(AlarmHapticPattern.allCases, id: \.self) { pattern in
                Button {
                    var settings = coordinator.snapshot.settings.value
                    settings.hapticPattern = pattern
                    coordinator.updateSettings(settings)
                    WKInterfaceDevice.current().play(pattern.watchHaptic)
                    // Deliberately leave the navigation path unchanged for repeated previews.
                } label: {
                    choice(pattern.title, selected: coordinator.snapshot.settings.value.hapticPattern == pattern)
                }
                .buttonStyle(.plain)
                .accessibilityValue(coordinator.snapshot.settings.value.hapticPattern == pattern ? "Selected" : "")
            }
        }
        .navigationTitle("Pattern")
    }

    private func numbers(title: String, range: ClosedRange<Int>, unit: String,
                         key: WritableKeyPath<AlarmSettings, Int>) -> some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(range), id: \.self) { number in
                    Button {
                        var settings = coordinator.snapshot.settings.value
                        settings[keyPath: key] = number
                        coordinator.updateSettings(settings)
                    } label: {
                        choice("\(number) \(unit)", selected: coordinator.snapshot.settings.value[keyPath: key] == number)
                    }
                    .buttonStyle(.plain).id(number)
                    .accessibilityValue(coordinator.snapshot.settings.value[keyPath: key] == number ? "Selected" : "")
                }
            }
            .onAppear { proxy.scrollTo(coordinator.snapshot.settings.value[keyPath: key], anchor: .center) }
        }
        .navigationTitle(title)
    }

    private func choice(_ text: String, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.body).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Image(systemName: "checkmark").font(.caption).opacity(selected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .contentShape(Rectangle())
    }
}
