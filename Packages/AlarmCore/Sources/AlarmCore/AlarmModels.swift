// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum AlarmError: Error, LocalizedError, Sendable {
    case invalidSettings, invalidOccurrence, unavailable, timedOut, dismissed, alreadyArmed
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSettings: "Choose a valid wake time, a 1–30 minute fallback, and a 1–60 second haptic interval."
        case .invalidOccurrence: "Choose a wake time within the next 36 hours."
        case .unavailable: "Open Alarm Beans on your paired devices and check their connection."
        case .timedOut: "The other device did not confirm. Check both apps before trying again."
        case .dismissed: "This alarm has already been dismissed."
        case .alreadyArmed: "Dismiss the current alarm before setting another."
        case .message(let text): text
        }
    }
}

public struct AlarmSettings: Codable, Equatable, Sendable {
    public var hour: Int
    public var minute: Int
    public var fallbackMinutes: Int
    public var hapticSeconds: Int
    public var hapticPattern: AlarmHapticPattern

    public init(hour: Int = 7, minute: Int = 0, fallbackMinutes: Int = 5, hapticSeconds: Int = 5,
                hapticPattern: AlarmHapticPattern = .notification) {
        self.hour = hour
        self.minute = minute
        self.fallbackMinutes = fallbackMinutes
        self.hapticSeconds = hapticSeconds
        self.hapticPattern = hapticPattern
    }

    private enum CodingKeys: String, CodingKey { case hour, minute, fallbackMinutes, hapticSeconds, hapticPattern }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hour = try values.decode(Int.self, forKey: .hour)
        minute = try values.decode(Int.self, forKey: .minute)
        fallbackMinutes = try values.decode(Int.self, forKey: .fallbackMinutes)
        hapticSeconds = try values.decode(Int.self, forKey: .hapticSeconds)
        // Builds before pattern selection have no field, including saved occurrences.
        hapticPattern = try values.decodeIfPresent(AlarmHapticPattern.self, forKey: .hapticPattern) ?? .notification
    }

    public func validate() throws {
        guard (0...23).contains(hour), (0...59).contains(minute),
              (1...30).contains(fallbackMinutes), (1...60).contains(hapticSeconds) else {
            throw AlarmError.invalidSettings
        }
    }

    public func nextOccurrence(after now: Date, calendar: Calendar = .current) throws -> AlarmOccurrence {
        try validate()
        guard let date = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else { throw AlarmError.invalidOccurrence }
        return try AlarmOccurrence(wakeTime: date, settings: self, now: now)
    }
}

public struct AlarmOccurrence: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let wakeTime: Date
    public let settings: AlarmSettings
    public let createdAt: Date
    public var fallbackTime: Date { wakeTime.addingTimeInterval(Double(settings.fallbackMinutes * 60)) }
    public var watchExpiry: Date { wakeTime.addingTimeInterval(30 * 60) }

    public init(id: UUID = UUID(), wakeTime: Date, settings: AlarmSettings, now: Date) throws {
        self.id = id
        self.wakeTime = wakeTime
        self.settings = settings
        self.createdAt = now
        try validate(at: now)
    }

    public func validate(at now: Date) throws {
        try settings.validate()
        guard wakeTime > now, wakeTime.timeIntervalSince(now) <= 36 * 3600,
              wakeTime.timeIntervalSince1970.isFinite else { throw AlarmError.invalidOccurrence }
    }
}

public enum AlarmPhase: String, Codable, Sendable {
    case preparing, armed, alerting, cancellationPending, dismissed, failed
}

public struct AlarmRecord: Codable, Equatable, Sendable {
    public var occurrence: AlarmOccurrence
    public var phase: AlarmPhase
    public var phoneScheduled: Bool
    public var watchScheduled: Bool
    public var detail: String?

    public init(occurrence: AlarmOccurrence, phase: AlarmPhase = .preparing,
                phoneScheduled: Bool = false, watchScheduled: Bool = false, detail: String? = nil) {
        self.occurrence = occurrence
        self.phase = phase
        self.phoneScheduled = phoneScheduled
        self.watchScheduled = watchScheduled
        self.detail = detail
    }

    public var blocksNewAlarm: Bool {
        phase != .dismissed && (phase != .failed || phoneScheduled || watchScheduled)
    }

    public func complicationTime(at now: Date) -> Date? {
        guard (phase == .armed || phase == .alerting), phoneScheduled, watchScheduled,
              now < occurrence.watchExpiry else { return nil }
        return occurrence.wakeTime
    }
}

public struct SettingsUpdate: Codable, Equatable, Sendable {
    public var value: AlarmSettings
    public var timestamp: Date
    public var id: UUID

    public init(value: AlarmSettings = .init(), timestamp: Date = .distantPast, id: UUID = UUID()) {
        self.value = value
        self.timestamp = timestamp
        self.id = id
    }

    public func isNewer(than other: SettingsUpdate) -> Bool {
        timestamp > other.timestamp || (timestamp == other.timestamp && id.uuidString > other.id.uuidString)
    }
}

public struct AlarmSnapshot: Codable, Equatable, Sendable {
    public var settings: SettingsUpdate = .init()
    public var record: AlarmRecord?
    // Tombstones are retained: queued messages must never resurrect old occurrences.
    public var dismissedIDs: Set<UUID> = []
    public var pendingCancellations: Set<UUID> = []

    public init() {}

    public mutating func dismiss(_ id: UUID) {
        dismissedIDs.insert(id)
        pendingCancellations.insert(id)
        if record?.occurrence.id == id {
            record?.phase = .cancellationPending
            record?.detail = "Cancellation pending on the other device. Its alarm may still alert."
        }
    }

    public mutating func acknowledgeCancellation(_ id: UUID) {
        pendingCancellations.remove(id)
        if record?.occurrence.id == id {
            record?.phase = .dismissed
            record?.phoneScheduled = false
            record?.watchScheduled = false
            record?.detail = nil
        }
    }

    public func mayPrepare(_ occurrence: AlarmOccurrence) throws {
        if dismissedIDs.contains(occurrence.id) { throw AlarmError.dismissed }
        if let record, record.blocksNewAlarm, record.occurrence.id != occurrence.id {
            throw AlarmError.alreadyArmed
        }
    }
}

