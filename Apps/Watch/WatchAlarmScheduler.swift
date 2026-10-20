// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import WatchKit

@MainActor final class WatchAlarmScheduler: NSObject, AlarmScheduling, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?
    private var occurrenceID: UUID?
    private var expectedInvalidations: Set<ObjectIdentifier> = []
    var coordinator: PairCoordinator?

    func schedule(_ occurrence: AlarmOccurrence) async throws {
        guard WKApplication.shared().applicationState == .active else {
            throw AlarmError.message("Keep the Watch app open until both alarms are armed.")
        }
        try occurrence.validate(at: Date())
        if let session, session.state != .invalid { throw AlarmError.alreadyArmed }
        let runtime = WKExtendedRuntimeSession()
        runtime.delegate = self
        session = runtime
        occurrenceID = occurrence.id
        runtime.start(at: occurrence.wakeTime)
        await Task.yield()
        guard runtime.state == .scheduled || runtime.state == .running else {
            throw AlarmError.message("watchOS did not schedule the haptic alarm. Check alarm auto-launch settings.")
        }
    }

    func cancel(_ id: UUID) async throws {
        guard occurrenceID == id, let session else {
            // A cold process may not receive the scheduled session until its start date.
            // The durable tombstone will suppress haptics when watchOS delivers it.
            return
        }
        guard session.state != .invalid else { self.session = nil; return }
        guard WKApplication.shared().applicationState == .active else {
            throw AlarmError.message("Open Alarm Beans on the Watch to finish stopping its session.")
        }
        expectedInvalidations.insert(ObjectIdentifier(session))
        session.invalidate()
        self.session = nil
        occurrenceID = nil
    }

    func scheduledIDs() async throws -> Set<UUID>? { nil }

    func restore(_ runtime: WKExtendedRuntimeSession) {
        // Set the delegate synchronously, before returning to watchOS.
        session = runtime
        runtime.delegate = self
        occurrenceID = coordinator?.snapshot.record?.occurrence.id
        if runtime.state == .running { beginHaptics(runtime) }
    }

    private func beginHaptics(_ runtime: WKExtendedRuntimeSession) {
        guard runtime.state == .running,
              let coordinator, let record = coordinator.snapshot.record,
              !coordinator.snapshot.dismissedIDs.contains(record.occurrence.id),
              record.watchScheduled, record.phoneScheduled,
              record.phase == .armed || record.phase == .alerting,
              Date() < record.occurrence.watchExpiry else {
            // Never alert for a dismissed or incompletely armed occurrence.
            if WKApplication.shared().applicationState == .active {
                expectedInvalidations.insert(ObjectIdentifier(runtime))
                runtime.invalidate()
            }
            return
        }
        occurrenceID = record.occurrence.id
        let interval = Double(record.occurrence.settings.hapticSeconds)
        coordinator.markAlerting(record.occurrence.id)
        runtime.notifyUser(hapticType: .notification, repeatHandler: { _ in interval })
    }

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor [weak self] in self?.beginHaptics(extendedRuntimeSession) }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor [weak self] in
            guard let self, let id = occurrenceID else { return }
            coordinator?.reportRuntimeFailure(id, detail: "The Watch haptic session has reached its time limit.")
        }
    }

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                           didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                           error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if expectedInvalidations.remove(ObjectIdentifier(extendedRuntimeSession)) != nil { return }
            guard session === extendedRuntimeSession, let id = occurrenceID else { return }
            session = nil
            occurrenceID = nil
            guard let coordinator, !coordinator.snapshot.dismissedIDs.contains(id) else { return }
            if let error {
                coordinator.reportRuntimeFailure(id, detail: error.localizedDescription)
            } else if reason != .none || Date() >= (coordinator.snapshot.record?.occurrence.watchExpiry ?? .distantPast) {
                coordinator.reportRuntimeFailure(id, detail: "The Watch haptic session expired.")
            } else {
                // Includes the system alarm alert's Stop button.
                await coordinator.dismiss(id)
            }
        }
    }
}

