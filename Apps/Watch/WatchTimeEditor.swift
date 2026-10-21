// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import SwiftUI
import WatchKit

struct WatchTimeEditor: View {
    @Binding var settings: AlarmSettings
    @Environment(\.locale) private var locale
    @State private var dial = CrownTimeDial()
    @FocusState private var crownFocused: Bool

    private var uses24Hour: Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
        return !template.contains("a")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            field(.hour)
            Text(":").accessibilityHidden(true)
            field(.minute)
            if !uses24Hour {
                Button {
                    settings.hour = (settings.hour + 12) % 24
                    select(dial.field)
                } label: {
                    Text(settings.hour < 12 ? "AM" : "PM")
                        .font(.caption2.weight(.semibold))
                        .frame(minWidth: 30, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AM or PM")
                .accessibilityValue(settings.hour < 12 ? "AM" : "PM")
            }
        }
        .font(.system(size: 44, weight: .medium, design: .rounded))
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        .focusable().focused($crownFocused)
        .digitalCrownRotation(crownBinding, from: -CrownTimeDial.limit, through: CrownTimeDial.limit,
                              by: 1, sensitivity: .low, isContinuous: true, isHapticFeedbackEnabled: false)
        // Rebuild the Crown sequencer on a selection change. Old callbacks carry
        // the old generation and cannot edit either field after the switch.
        .id(dial.generation)
        .onAppear { crownFocused = true }
        .accessibilityIdentifier("alarm.time.editor")
    }

    private func select(_ field: TimeDialField) {
        dial.select(field)
        crownFocused = true
    }

    private var crownBinding: Binding<Double> {
        let generation = dial.generation
        return Binding(get: { dial.position }, set: { position in
            var value = settings
            if dial.move(to: position, generation: generation, settings: &value, uses24Hour: uses24Hour) {
                settings = value
                WKInterfaceDevice.current().play(.click)
            }
        })
    }

    private func field(_ field: TimeDialField) -> some View {
        let isHour = field == .hour
        let number = isHour ? (uses24Hour ? settings.hour : (settings.hour % 12 == 0 ? 12 : settings.hour % 12)) : settings.minute
        return Text(isHour && !uses24Hour ? String(number) : String(format: "%02d", number))
            .padding(.horizontal, 3).padding(.vertical, 5)
            .background(dial.field == field ? Color.accentColor.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .bottom) {
                if dial.field == field { Capsule().fill(Color.accentColor).frame(height: 2) }
            }
            .contentShape(Rectangle())
            .onTapGesture { select(field) }
            .accessibilityLabel(isHour ? "Hour" : "Minute")
            .accessibilityValue(String(number))
            .accessibilityHint("Turn the Digital Crown to change")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { select(field) }
            .accessibilityAdjustableAction { direction in
                select(field)
                let step = direction == .increment ? 1 : -1
                if isHour { settings.setDialHour(settings.hour + step, uses24Hour: uses24Hour) }
                else { settings.setDialMinute(settings.minute + step) }
            }
    }
}
