// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct AlarmMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case prepareFallback, confirmWatch, cancel, cancellationAcknowledged, settings, state, query, syncHomeAssistant
    }
    public var kind: Kind
    public var occurrence: AlarmOccurrence?
    public var id: UUID?
    public var settings: SettingsUpdate?
    public var record: AlarmRecord?

    public init(_ kind: Kind, occurrence: AlarmOccurrence? = nil, id: UUID? = nil,
                settings: SettingsUpdate? = nil, record: AlarmRecord? = nil) {
        self.kind = kind
        self.occurrence = occurrence
        self.id = id
        self.settings = settings
        self.record = record
    }
}

public struct AlarmReply: Codable, Sendable {
    public let success: Bool
    public let detail: String?
    public let record: AlarmRecord?
    public let settings: SettingsUpdate?
    public init(success: Bool = true, detail: String? = nil, record: AlarmRecord? = nil, settings: SettingsUpdate? = nil) {
        self.success = success
        self.detail = detail
        self.record = record
        self.settings = settings
    }
}

