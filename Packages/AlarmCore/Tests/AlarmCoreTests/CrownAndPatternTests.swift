// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import AlarmCore

@Test func crownRequiresMoreMovementForHoursThanMinutes() {
    var input = CrownTimeDial()
    var settings = AlarmSettings(hour: 7, minute: 0)
    #expect(!input.move(to: 3, generation: 0, settings: &settings, uses24Hour: false))
    #expect(settings.hour == 7)
    #expect(input.move(to: 4, generation: 0, settings: &settings, uses24Hour: false))
    #expect(settings.hour == 8)
    input.select(.minute)
    let generation = input.generation
    #expect(!input.move(to: 1, generation: generation, settings: &settings, uses24Hour: false))
    #expect(input.move(to: 2, generation: generation, settings: &settings, uses24Hour: false))
    #expect(settings.minute == 1)
    #expect(settings.hour == 8)
}

@Test func switchingFieldsRejectsOldCrownCallbacksAndClearsPartialTurns() {
    var input = CrownTimeDial()
    var settings = AlarmSettings(hour: 12, minute: 59)
    _ = input.move(to: 3, generation: 0, settings: &settings, uses24Hour: false)
    input.select(.minute)
    let minuteGeneration = input.generation
    #expect(!input.move(to: 8, generation: 0, settings: &settings, uses24Hour: false))
    #expect(settings.hour == 12)
    #expect(input.position == 0)
    #expect(input.move(to: 2, generation: minuteGeneration, settings: &settings, uses24Hour: false))
    #expect(settings.minute == 0)
    #expect(settings.hour == 12)
    input.select(.hour)
    let hourGeneration = input.generation
    #expect(!input.move(to: 4, generation: minuteGeneration, settings: &settings, uses24Hour: false))
    #expect(input.move(to: 4, generation: hourGeneration, settings: &settings, uses24Hour: false))
    #expect(settings.hour == 13)
    #expect(settings.minute == 0)
}

@Test func crownWrapsBackwardsAndPreservesAMPM() {
    var input = CrownTimeDial()
    var settings = AlarmSettings(hour: 12, minute: 0)
    _ = input.move(to: -4, generation: 0, settings: &settings, uses24Hour: false)
    #expect(settings.hour == 23)
    input.select(.minute)
    _ = input.move(to: -2, generation: input.generation, settings: &settings, uses24Hour: false)
    #expect(settings.minute == 59)
    #expect(settings.hour == 23)
    input.select(.hour)
    _ = input.move(to: 4, generation: input.generation, settings: &settings, uses24Hour: true)
    #expect(settings.hour == 0)
}

@Test func rapidCrownSwitchingCannotChangeOldField() {
    var input = CrownTimeDial()
    var settings = AlarmSettings()
    for _ in 0..<20 {
        let old = input.generation
        input.select(.minute)
        _ = input.move(to: 40, generation: old, settings: &settings, uses24Hour: false)
        _ = input.move(to: 2, generation: input.generation, settings: &settings, uses24Hour: false)
        let minute = input.generation
        input.select(.hour)
        _ = input.move(to: 20, generation: minute, settings: &settings, uses24Hour: false)
    }
    #expect(settings.hour == 7)
    #expect(settings.minute == 20)
}

@Test func settingsFromEarlierBuildDefaultToNotification() throws {
    let legacy = Data(#"{"hour":7,"minute":30,"fallbackMinutes":5,"hapticSeconds":5}"#.utf8)
    let settings = try JSONDecoder().decode(AlarmSettings.self, from: legacy)
    #expect(settings.hapticPattern == .notification)
    #expect(settings.hour == 7 && settings.minute == 30)
    for pattern in AlarmHapticPattern.allCases {
        let value = AlarmSettings(hapticPattern: pattern)
        #expect(try JSONDecoder().decode(AlarmSettings.self, from: JSONEncoder().encode(value)) == value)
    }
}

@Test func upgradeRestoresLegacyActiveOccurrence() throws {
    let now = Date()
    var state = AlarmSnapshot()
    state.record = AlarmRecord(occurrence: try AlarmOccurrence(wakeTime: now.addingTimeInterval(3600), settings: .init(), now: now),
                               phase: .armed, phoneScheduled: true, watchScheduled: true)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    var settings = try #require(json["settings"] as? [String: Any])
    var value = try #require(settings["value"] as? [String: Any])
    value.removeValue(forKey: "hapticPattern")
    settings["value"] = value
    json["settings"] = settings
    var record = try #require(json["record"] as? [String: Any])
    var occurrence = try #require(record["occurrence"] as? [String: Any])
    occurrence["settings"] = value
    record["occurrence"] = occurrence
    json["record"] = record
    let restored = try JSONDecoder().decode(AlarmSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(restored == state)
}
