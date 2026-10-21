// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import SwiftUI

struct WatchTimeEditor: View {
    @Binding var settings: AlarmSettings
    @Environment(\.locale) private var locale
    @FocusState private var selected: Field?
    private enum Field: Hashable { case hour, minute }

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
        .onAppear { selected = .hour }
        .accessibilityIdentifier("alarm.time.editor")
    }

    private func field(_ field: Field) -> some View {
        let isHour = field == .hour
        let number = isHour ? (uses24Hour ? settings.hour : (settings.hour % 12 == 0 ? 12 : settings.hour % 12)) : settings.minute
        return Text(isHour && !uses24Hour ? String(number) : String(format: "%02d", number))
            .padding(.horizontal, 3).padding(.vertical, 5)
            .background(selected == field ? Color.accentColor.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .bottom) {
                if selected == field { Capsule().fill(Color.accentColor).frame(height: 2) }
            }
            .contentShape(Rectangle())
            .focusable().focused($selected, equals: field)
            .digitalCrownRotation(dial(field), from: 0, through: isHour ? (uses24Hour ? 23 : 11) : 59,
                                  by: 1, sensitivity: .low, isContinuous: true, isHapticFeedbackEnabled: true)
            .onTapGesture { selected = field }
            .accessibilityLabel(isHour ? "Hour" : "Minute")
            .accessibilityValue(String(number))
            .accessibilityHint("Turn the Digital Crown to change")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1 : -1
                let binding = dial(field)
                binding.wrappedValue += Double(step)
            }
    }

    private func dial(_ field: Field) -> Binding<Double> {
        Binding(get: {
            Double(field == .hour ? (uses24Hour ? settings.hour : settings.hour % 12) : settings.minute)
        }, set: { value in
            if field == .hour {
                settings.setDialHour(Int(value.rounded()), uses24Hour: uses24Hour)
            } else {
                settings.setDialMinute(Int(value.rounded()))
            }
        })
    }
}
