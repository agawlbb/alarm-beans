// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct HomeAssistantPairing: Codable, Sendable {
    public let url: URL
    public let token: String
    public func validate() throws {
        guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              (32...128).contains(token.count), token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { throw AlarmError.message("Invalid Home Assistant pairing code.") }
    }
}

public struct HomeAssistantValues: Codable, Equatable, Sendable {
    public var wake_time: String
    public var haptic_interval: Int
    public var iphone_offset: Int
    public init(_ settings: AlarmSettings) {
        wake_time = String(format: "%02d:%02d", settings.hour, settings.minute)
        haptic_interval = settings.hapticSeconds
        iphone_offset = settings.fallbackMinutes
    }
}

public struct HomeAssistantRequest: Codable, Sendable {
    public let id: UUID
    public let field: String
    public let value: String
    public init(id: UUID = UUID(), field: String, value: String) { self.id = id; self.field = field; self.value = value }
    public func applying(to settings: AlarmSettings) throws -> AlarmSettings {
        var result = settings
        switch field {
        case "wake_time":
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }),
                  let hour = Int(parts[0]), let minute = Int(parts[1]) else { throw AlarmError.invalidSettings }
            result.hour = hour; result.minute = minute
        case "haptic_interval":
            guard let number = Int(value) else { throw AlarmError.invalidSettings }
            result.hapticSeconds = number
        case "iphone_offset":
            guard let number = Int(value) else { throw AlarmError.invalidSettings }
            result.fallbackMinutes = number
        default: throw AlarmError.invalidSettings
        }
        try result.validate()
        return result
    }
}

public struct HomeAssistantReceipt: Codable, Sendable {
    public let id: UUID
    public let accepted: Bool
    public let reason: String?
    public init(id: UUID, accepted: Bool, reason: String? = nil) { self.id = id; self.accepted = accepted; self.reason = reason }
}

public struct HomeAssistantReport: Codable, Sendable {
    public let values: HomeAssistantValues
    public let enabled: Bool
    public let locked: Bool
    public let receipts: [HomeAssistantReceipt]
    @MainActor public init(coordinator: PairCoordinator, receipts: [HomeAssistantReceipt]) {
        values = HomeAssistantValues(coordinator.displayedSettings)
        enabled = coordinator.confirmedArmed
        locked = !coordinator.settingsEditable
        self.receipts = receipts
    }
}

@MainActor public protocol HomeAssistantTransport: AnyObject {
    func exchange(_ report: HomeAssistantReport) async throws -> [HomeAssistantRequest]
}

@MainActor public protocol HomeAssistantJournal: AnyObject {
    var receipts: [HomeAssistantReceipt] { get }
    func save(_ receipts: [HomeAssistantReceipt]) throws
}

@MainActor public final class HomeAssistantSync {
    private let coordinator: PairCoordinator
    private let transport: any HomeAssistantTransport
    private let journal: any HomeAssistantJournal
    private var syncing = false
    public init(coordinator: PairCoordinator, transport: any HomeAssistantTransport, journal: any HomeAssistantJournal) {
        self.coordinator = coordinator; self.transport = transport; self.journal = journal
    }
    public func synchronize() async throws {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let previous = journal.receipts
        let requests = try await transport.exchange(HomeAssistantReport(coordinator: coordinator, receipts: previous))
        // Keep the old receipts until every response is handled; a duplicated
        // response can never apply a previously consumed command again.
        var receipts = previous
        for request in requests {
            if receipts.contains(where: { $0.id == request.id }) { continue }
            guard receipts.count < 256 else { throw AlarmError.message("Home Assistant receipt journal is full.") }
            receipts.append(HomeAssistantReceipt(id: request.id, accepted: false, reason: "Interrupted before acceptance"))
            try journal.save(receipts) // durable consumption BEFORE any await or settings mutation
            let receipt: HomeAssistantReceipt
            do {
                let value = try request.applying(to: coordinator.displayedSettings)
                let accepted = try await coordinator.applyExternalSettings(value)
                receipt = HomeAssistantReceipt(id: request.id, accepted: accepted,
                    reason: accepted ? nil : "Alarm locked or settings request expired")
            } catch {
                receipt = HomeAssistantReceipt(id: request.id, accepted: false, reason: "Watch unavailable or settings invalid")
            }
            receipts[receipts.count - 1] = receipt
            try journal.save(receipts)
        }
        if !receipts.isEmpty {
            // The server never reissues claimed requests. Do not consume new
            // commands from the acknowledgement response: they stay pending.
            _ = try await transport.exchange(HomeAssistantReport(coordinator: coordinator, receipts: receipts))
            try journal.save([])
        }
    }
}
