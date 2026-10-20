// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import AlarmCore

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func calendar(_ zone: String = "UTC") -> Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(identifier: zone)!
    return result
}

@Test func nextWakeAndFallbackCrossMidnight() throws {
    let alarm = try AlarmSettings(hour: 23, minute: 58).nextOccurrence(
        after: date("2026-10-20T23:57:00Z"), calendar: calendar())
    #expect(alarm.wakeTime == date("2026-10-20T23:58:00Z"))
    #expect(alarm.fallbackTime == date("2026-10-21T00:03:00Z"))
}

@Test func pastOrExactTimeUsesTomorrow() throws {
    let alarm = try AlarmSettings().nextOccurrence(after: date("2026-10-20T07:00:00Z"), calendar: calendar())
    #expect(alarm.wakeTime == date("2026-10-21T07:00:00Z"))
}

@Test func springGapUsesNextValidTime() throws {
    let alarm = try AlarmSettings(hour: 2, minute: 30).nextOccurrence(
        after: date("2027-03-14T05:00:00Z"), calendar: calendar("America/New_York"))
    #expect(alarm.wakeTime == date("2027-03-14T07:00:00Z"))
}

@Test func autumnRepeatUsesFirstOccurrence() throws {
    let alarm = try AlarmSettings(hour: 1, minute: 30).nextOccurrence(
        after: date("2026-11-01T04:00:00Z"), calendar: calendar("America/New_York"))
    #expect(alarm.wakeTime == date("2026-11-01T05:30:00Z"))
}

@Test func countdownRoundsUpAndNeverGoesNegative() {
    let now = date("2026-10-20T00:00:00Z")
    #expect(RemainingTime(until: now.addingTimeInterval(8 * 3600 + 14 * 60 + 1), now: now).text == "in 8 hours 15 minutes")
    #expect(RemainingTime(until: now.addingTimeInterval(1), now: now).text == "in 0 hours 1 minute")
    #expect(RemainingTime(until: now, now: now).isDue)
    #expect(RemainingTime(until: now.addingTimeInterval(-120), now: now).text == "Due now")
}

@Test func settingsBoundaries() throws {
    try AlarmSettings(hour: 23, minute: 59, fallbackMinutes: 30, hapticSeconds: 60).validate()
    #expect(throws: AlarmError.self) { try AlarmSettings(fallbackMinutes: 0).validate() }
    #expect(throws: AlarmError.self) { try AlarmSettings(hapticSeconds: 61).validate() }
    #expect(throws: AlarmError.self) { try AlarmSettings(hour: 24).validate() }
}

@Test func watchSchedulingHorizon() {
    let now = Date()
    #expect(throws: AlarmError.self) {
        try AlarmOccurrence(wakeTime: now.addingTimeInterval(36 * 3600 + 1), settings: .init(), now: now)
    }
}

@Test func unconfirmedAndDismissedAlarmsHaveNoComplicationTime() throws {
    let now = Date()
    let alarm = try AlarmOccurrence(wakeTime: now.addingTimeInterval(3600), settings: .init(), now: now)
    var record = AlarmRecord(occurrence: alarm)
    #expect(record.complicationTime(at: now) == nil)
    record.phoneScheduled = true
    record.watchScheduled = true
    record.phase = .armed
    #expect(record.complicationTime(at: now) == alarm.wakeTime)
    #expect(record.complicationTime(at: alarm.watchExpiry) == nil)
    record.phase = .alerting
    #expect(record.complicationTime(at: alarm.wakeTime) == alarm.wakeTime)
    record.phase = .cancellationPending
    #expect(record.complicationTime(at: now) == nil)
}

@Test func cancellationSurvivesRoundTripAndRejectsLatePrepare() throws {
    let now = Date()
    let alarm = try AlarmOccurrence(wakeTime: now.addingTimeInterval(3600), settings: .init(), now: now)
    var state = AlarmSnapshot()
    state.record = AlarmRecord(occurrence: alarm, phase: .armed, phoneScheduled: true, watchScheduled: true)
    state.dismiss(alarm.id)
    state.dismiss(alarm.id)
    var restored = try JSONDecoder().decode(AlarmSnapshot.self, from: JSONEncoder().encode(state))
    #expect(restored.pendingCancellations == [alarm.id])
    #expect(throws: AlarmError.self) { try restored.mayPrepare(alarm) }
    restored.acknowledgeCancellation(alarm.id)
    #expect(restored.record?.phase == .dismissed)
    #expect(restored.pendingCancellations.isEmpty)
    #expect(throws: AlarmError.self) { try restored.mayPrepare(alarm) }
}

@Test func lateCancellationDoesNotDismissANewerAlarm() throws {
    let now = Date()
    let old = try AlarmOccurrence(wakeTime: now.addingTimeInterval(3600), settings: .init(), now: now)
    let new = try AlarmOccurrence(wakeTime: now.addingTimeInterval(7200), settings: .init(), now: now)
    var state = AlarmSnapshot()
    state.record = AlarmRecord(occurrence: new, phase: .armed, phoneScheduled: true, watchScheduled: true)
    state.dismiss(old.id)
    state.acknowledgeCancellation(old.id)
    #expect(state.record?.occurrence.id == new.id)
    #expect(state.record?.phase == .armed)
    #expect(throws: AlarmError.self) { try state.mayPrepare(old) }
}

@Test func duplicatePreparationIsAllowedButSecondAlarmIsNot() throws {
    let now = Date()
    let first = try AlarmOccurrence(wakeTime: now.addingTimeInterval(3600), settings: .init(), now: now)
    let second = try AlarmOccurrence(wakeTime: now.addingTimeInterval(7200), settings: .init(), now: now)
    var state = AlarmSnapshot()
    state.record = AlarmRecord(occurrence: first)
    try state.mayPrepare(first)
    #expect(throws: AlarmError.self) { try state.mayPrepare(second) }
}

@Test func settingsUpdatesHaveDeterministicOrdering() {
    let time = Date()
    let low = SettingsUpdate(timestamp: time, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let high = SettingsUpdate(timestamp: time, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    #expect(high.isNewer(than: low))
    #expect(!low.isNewer(than: high))
    #expect(!high.isNewer(than: high))
}
