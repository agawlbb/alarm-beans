// SPDX-License-Identifier: MPL-2.0
import Foundation
import Observation

public enum DeviceRole: Sendable { case phone, watch }

@MainActor public protocol AlarmScheduling: AnyObject {
    func schedule(_ occurrence: AlarmOccurrence) async throws
    func cancel(_ id: UUID) async throws
    // nil means this platform cannot enumerate scheduled system alarms.
    func scheduledIDs() async throws -> Set<UUID>?
}

@MainActor public protocol AlarmLink: AnyObject {
    var onMessage: ((AlarmMessage) async -> AlarmReply)? { get set }
    var onReconnect: (() async -> Void)? { get set }
    func request(_ message: AlarmMessage) async throws -> AlarmReply
    func enqueue(_ message: AlarmMessage)
}

@MainActor public protocol AlarmPersistence: AnyObject {
    func load() throws -> AlarmSnapshot
    func save(_ snapshot: AlarmSnapshot) throws
}

@MainActor @Observable public final class PairCoordinator {
    public private(set) var snapshot: AlarmSnapshot
    public private(set) var busy = false
    public var issue: String?
    public let role: DeviceRole
    @ObservationIgnored private let scheduler: any AlarmScheduling
    @ObservationIgnored private let link: any AlarmLink
    @ObservationIgnored private let persistence: any AlarmPersistence
    @ObservationIgnored private var preparingIDs: Set<UUID> = []
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var storageHealthy = true
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored public var onAppOpenSync: (() async -> Void)?

    public var settingsEditable: Bool {
        storageHealthy && !busy && snapshot.pendingCancellations.isEmpty &&
        snapshot.record?.blocksNewAlarm != true &&
        snapshot.record?.phoneScheduled != true && snapshot.record?.watchScheduled != true
    }

    public var displayedSettings: AlarmSettings {
        if let record = snapshot.record,
           record.blocksNewAlarm || record.phoneScheduled || record.watchScheduled { return record.occurrence.settings }
        return snapshot.settings.value
    }

    public var confirmedArmed: Bool {
        guard let record = snapshot.record else { return false }
        return (record.phase == .armed || record.phase == .alerting) && record.phoneScheduled && record.watchScheduled
    }

    public init(role: DeviceRole, scheduler: any AlarmScheduling,
                link: any AlarmLink, persistence: any AlarmPersistence) {
        self.role = role
        self.scheduler = scheduler
        self.link = link
        self.persistence = persistence
        do { snapshot = try persistence.load() }
        catch {
            snapshot = AlarmSnapshot()
            storageHealthy = false
            issue = "Saved alarm state could not be read. Check system alarms before using Alarm Beans."
        }
        link.onMessage = { [weak self] message in
            guard let self else { return AlarmReply(success: false, detail: "App unavailable") }
            return await self.receive(message)
        }
        link.onReconnect = { [weak self] in await self?.synchronize() }
    }

    private func persist() throws {
        do {
            try persistence.save(snapshot)
            onChange?()
        } catch {
            storageHealthy = false
            issue = "Alarm state could not be saved. Check both devices; an alarm may still be scheduled."
            throw error
        }
    }

    @discardableResult public func updateSettings(_ value: AlarmSettings) -> Bool {
        guard settingsEditable else { return false }
        let previous = snapshot.settings
        do {
            try value.validate()
            snapshot.settings = SettingsUpdate(value: value, timestamp: Date(), epoch: previous.epoch)
            try persist()
            link.enqueue(AlarmMessage(.settings, settings: snapshot.settings))
            return true
        } catch {
            snapshot.settings = previous
            issue = error.localizedDescription
            return false
        }
    }

    // HA acknowledges a change only after the Watch has accepted it. Never
    // enqueue an external edit for replay after an offline/locked rejection.
    public func applyExternalSettings(_ value: AlarmSettings) async throws -> Bool {
        guard role == .phone, settingsEditable else { return false }
        try value.validate()
        let baseID = snapshot.settings.id
        let update = SettingsUpdate(value: value, timestamp: Date(), epoch: snapshot.settings.epoch)
        let reply = try await link.request(AlarmMessage(.settings, settings: update))
        guard reply.success, reply.settings?.id == update.id else { return false }
        if !settingsEditable {
            // The Watch may have captured this accepted edit before its reply
            // reached us. In that case prepareFallback already stored it.
            return confirmedArmed || snapshot.record?.phase == .preparing
                ? snapshot.record?.occurrence.settings == value : false
        }
        guard snapshot.settings.epoch == update.epoch else { return false }
        guard snapshot.settings.id == baseID || snapshot.settings.id == update.id else { return false }
        let previous = snapshot.settings
        snapshot.settings = update
        do { try persist() } catch { snapshot.settings = previous; throw error }
        return true
    }

    public func arm(now: Date = Date(), calendar: Calendar = .current) async {
        guard role == .watch, !busy, storageHealthy else { return }
        busy = true
        issue = nil
        defer { busy = false }
        var occurrence: AlarmOccurrence?
        do {
            guard snapshot.pendingCancellations.isEmpty else { throw AlarmError.alreadyArmed }
            let captured = snapshot.settings.value
            let alarm = try captured.nextOccurrence(after: now, calendar: calendar)
            try snapshot.mayPrepare(alarm)
            occurrence = alarm
            snapshot.record = AlarmRecord(occurrence: alarm)
            snapshot.settings.epoch = UUID()
            try persist()

            try check(await link.request(AlarmMessage(.prepareFallback, occurrence: alarm, settings: snapshot.settings)))
            try ensureLive(alarm.id)
            snapshot.record?.phoneScheduled = true
            try persist()

            try await scheduler.schedule(alarm)
            try ensureLive(alarm.id)
            snapshot.record?.watchScheduled = true
            try persist()
            try check(await link.request(AlarmMessage(.confirmWatch, id: alarm.id)))
            try ensureLive(alarm.id)
            snapshot.record?.phase = .armed
            try persist()
        } catch {
            let cause = error.localizedDescription
            if let occurrence {
                await dismiss(occurrence.id)
                if snapshot.record?.phase == .dismissed {
                    snapshot.record?.phase = .failed
                    snapshot.record?.detail = cause
                    try? persist()
                }
            }
            issue = "Could not arm both alarms. \(cause)"
        }
    }

    private func check(_ reply: AlarmReply) throws {
        if !reply.success { throw AlarmError.message(reply.detail ?? "The other device could not complete the action.") }
    }

    private func ensureLive(_ id: UUID) throws {
        guard !snapshot.dismissedIDs.contains(id), snapshot.record?.occurrence.id == id else {
            throw AlarmError.dismissed
        }
    }

    public func dismissCurrent() async {
        guard let id = snapshot.record?.occurrence.id else { return }
        await dismiss(id)
    }

    public func dismiss(_ id: UUID) async {
        // Save the tombstone before any await or side effect.
        snapshot.dismiss(id)
        do { try persist() } catch {
            // A disk failure must not prevent the user from stopping a local alert.
            try? await scheduler.cancel(id)
            link.enqueue(AlarmMessage(.cancel, id: id))
            return
        }
        link.enqueue(AlarmMessage(.cancel, id: id))
        do {
            try await scheduler.cancel(id)
            markLocalStopped(id)
            try persist()
            let reply = try await link.request(AlarmMessage(.cancel, id: id))
            try check(reply)
            snapshot.acknowledgeCancellation(id)
            try persist()
            clearResolvedCancellationIssue()
        } catch {
            if snapshot.pendingCancellations.contains(id) {
                issue = "Cancellation pending. The other device's alarm may still alert. \(error.localizedDescription)"
            } else {
                clearResolvedCancellationIssue()
            }
        }
    }

    private func clearResolvedCancellationIssue() {
        if storageHealthy && snapshot.pendingCancellations.isEmpty,
           issue?.hasPrefix("Cancellation pending.") == true {
            issue = nil
        }
    }

    private func markLocalStopped(_ id: UUID) {
        guard snapshot.record?.occurrence.id == id else { return }
        if role == .phone { snapshot.record?.phoneScheduled = false }
        else { snapshot.record?.watchScheduled = false }
    }

    public func markAlerting(_ id: UUID) {
        guard !snapshot.dismissedIDs.contains(id), snapshot.record?.occurrence.id == id else { return }
        snapshot.record?.phase = .alerting
        try? persist()
    }

    public func reportRuntimeFailure(_ id: UUID, detail: String) {
        guard snapshot.record?.occurrence.id == id, !snapshot.dismissedIDs.contains(id) else { return }
        snapshot.record?.phase = .failed
        snapshot.record?.watchScheduled = false
        snapshot.record?.detail = detail + " The iPhone fallback remains scheduled."
        issue = snapshot.record?.detail
        try? persist()
        link.enqueue(AlarmMessage(.state, record: snapshot.record))
    }

    public func synchronize() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        for id in snapshot.pendingCancellations { await dismiss(id) }
        link.enqueue(AlarmMessage(.settings, settings: snapshot.settings))
        if role == .phone {
            await reconcilePhone()
        } else if let record = snapshot.record,
                  record.phase == .preparing || (record.phase == .armed && Date() >= record.occurrence.watchExpiry) {
            // An interrupted arm is never presented as confirmed; clean up both sides.
            if !busy { await dismiss(record.occurrence.id) }
        }
        do {
            if role == .watch { _ = try? await link.request(AlarmMessage(.syncHomeAssistant)) }
            let reply = try await link.request(AlarmMessage(.query))
            if reply.success, let record = reply.record { await adopt(record) }
            if role == .phone, settingsEditable, let update = reply.settings {
                try update.value.validate()
                if update.epoch != snapshot.settings.epoch || update.isNewer(than: snapshot.settings) {
                    snapshot.settings = update
                    try persist()
                }
            }
        } catch { /* Offline is expected; persisted alarms remain in force. */ }
    }

    public func reconcilePhone() async {
        guard role == .phone else { return }
        do {
            guard let ids = try await scheduler.scheduledIDs() else { return }
            if issue?.hasPrefix("Could not verify iPhone alarms.") == true { issue = nil }
            for id in snapshot.dismissedIDs.intersection(ids) { try await scheduler.cancel(id) }
            guard let record = snapshot.record else {
                // These IDs belong to this app's AlarmKit namespace.
                for id in ids { await dismiss(id) }
                return
            }
            if record.phoneScheduled && !ids.contains(record.occurrence.id) {
                await dismiss(record.occurrence.id)
            } else if record.phase == .preparing,
                      Date().timeIntervalSince(record.occurrence.createdAt) > 120 {
                await dismiss(record.occurrence.id)
            }
        } catch { issue = "Could not verify iPhone alarms. \(error.localizedDescription)" }
    }

    private func adopt(_ remote: AlarmRecord) async {
        let id = remote.occurrence.id
        if snapshot.dismissedIDs.contains(id) {
            if remote.phase != .dismissed && remote.phase != .cancellationPending {
                link.enqueue(AlarmMessage(.cancel, id: id))
            }
            return
        }
        // Only the Watch creates occurrences. Phone state must not arm a cold Watch.
        if role == .watch {
            if remote.phase == .dismissed || remote.phase == .cancellationPending {
                await dismiss(id)
            } else if snapshot.record?.occurrence.id == id, !remote.phoneScheduled {
                await dismiss(id)
            }
        } else {
            guard snapshot.record?.occurrence.id == id else { return }
            if remote.phase == .failed {
                snapshot.record?.phase = .failed
                snapshot.record?.watchScheduled = false
                snapshot.record?.detail = remote.detail
                try? persist()
            }
        }
    }

    public func receive(_ message: AlarmMessage) async -> AlarmReply {
        do {
            switch message.kind {
            case .prepareFallback:
                guard role == .phone, storageHealthy, let alarm = message.occurrence else { throw AlarmError.unavailable }
                try alarm.validate(at: Date())
                try snapshot.mayPrepare(alarm)
                if snapshot.record?.occurrence == alarm, snapshot.record?.phoneScheduled == true {
                    return AlarmReply(record: snapshot.record)
                }
                guard !preparingIDs.contains(alarm.id) else { throw AlarmError.message("Scheduling is already in progress.") }
                preparingIDs.insert(alarm.id)
                defer { preparingIDs.remove(alarm.id) }
                if let captured = message.settings, captured.value != alarm.settings { throw AlarmError.invalidSettings }
                snapshot.record = AlarmRecord(occurrence: alarm)
                if let captured = message.settings {
                    snapshot.settings = captured
                } else {
                    snapshot.settings = SettingsUpdate(value: alarm.settings, timestamp: Date(), epoch: UUID())
                }
                try persist()
                try await scheduler.schedule(alarm)
                // Stop may have arrived while AlarmKit was awaiting scheduling.
                if snapshot.dismissedIDs.contains(alarm.id) {
                    try await scheduler.cancel(alarm.id)
                    throw AlarmError.dismissed
                }
                snapshot.record?.phoneScheduled = true
                try persist()
            case .confirmWatch:
                guard role == .phone, let id = message.id else { throw AlarmError.unavailable }
                try ensureLive(id)
                guard snapshot.record?.phoneScheduled == true else { throw AlarmError.unavailable }
                snapshot.record?.watchScheduled = true
                snapshot.record?.phase = .armed
                try persist()
            case .cancel:
                guard let id = message.id else { throw AlarmError.invalidOccurrence }
                snapshot.dismiss(id)
                try persist()
                try await scheduler.cancel(id)
                snapshot.acknowledgeCancellation(id)
                try persist()
                link.enqueue(AlarmMessage(.cancellationAcknowledged, id: id))
            case .cancellationAcknowledged:
                if let id = message.id, snapshot.dismissedIDs.contains(id) {
                    // Receiving the ack does not excuse an unfinished local cancellation.
                    try await scheduler.cancel(id)
                    snapshot.acknowledgeCancellation(id)
                    try persist()
                    clearResolvedCancellationIssue()
                }
            case .settings:
                guard settingsEditable else { throw AlarmError.alreadyArmed }
                guard message.settings?.epoch == snapshot.settings.epoch else {
                    throw AlarmError.message("Settings request expired.")
                }
                if let update = message.settings, update.isNewer(than: snapshot.settings) {
                    try update.value.validate()
                    let previous = snapshot.settings
                    snapshot.settings = update
                    do { try persist() } catch { snapshot.settings = previous; throw error }
                }
            case .state:
                if let record = message.record { await adopt(record) }
            case .syncHomeAssistant:
                if role == .phone { await onAppOpenSync?() }
            case .query: break
            }
            return AlarmReply(record: snapshot.record, settings: snapshot.settings)
        } catch {
            return AlarmReply(success: false, detail: error.localizedDescription, record: snapshot.record)
        }
    }
}
