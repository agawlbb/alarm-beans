// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import WatchKit

@MainActor final class WatchAlarmScheduler: NSObject, AlarmScheduling, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?
    private var occurrenceID: UUID?
    private var schedulingID: UUID?
    private var schedulingError: Error?
    private var expectedInvalidations: Set<ObjectIdentifier> = []
    private var notifiedSessions: Set<ObjectIdentifier> = []
    var coordinator: PairCoordinator?

    func schedule(_ occurrence: AlarmOccurrence) async throws {
        guard WKApplication.shared().applicationState == .active else {
            throw AlarmError.message("Keep the Watch app open until both alarms are armed.")
        }
        try occurrence.validate(at: Date())
        if let session, session.state != .invalid { throw AlarmError.alreadyArmed }
        // Smart alarms use the alarm background mode and start(at:). The
        // auto-launch authorization API rejects this session type (error 10).
        if coordinator?.snapshot.dismissedIDs.contains(occurrence.id) == true { throw AlarmError.dismissed }
        let runtime = WKExtendedRuntimeSession()
        runtime.delegate = self
        session = runtime
        occurrenceID = occurrence.id
        schedulingID = occurrence.id
        schedulingError = nil
        defer {
            schedulingID = nil
            schedulingError = nil
        }
        runtime.start(at: occurrence.wakeTime)
        try await SchedulingConfirmation.wait {
            if let schedulingError { throw schedulingError }
            guard session === runtime, occurrenceID == occurrence.id,
                  coordinator?.snapshot.dismissedIDs.contains(occurrence.id) != true else {
                throw AlarmError.dismissed
            }
            // A pending state is not rejection. If invalidated, let the delegate
            // deliver the real watchOS error before the bounded wait expires.
            return runtime.state == .scheduled || runtime.state == .running
        }
    }

    private func schedulingFailure(_ error: Error) -> AlarmError {
        let error = error as NSError
        return .message("watchOS could not schedule the haptic alarm: \(error.localizedDescription) [\(error.domain) \(error.code)]")
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

    func refreshAlert() {
        if let session, session.state == .running { beginHaptics(session) }
    }

    private func beginHaptics(_ runtime: WKExtendedRuntimeSession) {
        guard !notifiedSessions.contains(ObjectIdentifier(runtime)) else { return }
        // A near-term wake may start during the final phone acknowledgment.
        // Wait for the paired arm to finish; onChange retries this method.
        if coordinator?.snapshot.record?.phase == .preparing { return }
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
        notifiedSessions.insert(ObjectIdentifier(runtime))
        coordinator.markAlerting(record.occurrence.id)
        runtime.notifyUser(hapticType: record.occurrence.settings.hapticPattern.watchHaptic,
                           repeatHandler: { _ in interval })
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
            notifiedSessions.remove(ObjectIdentifier(extendedRuntimeSession))
            if expectedInvalidations.remove(ObjectIdentifier(extendedRuntimeSession)) != nil { return }
            guard session === extendedRuntimeSession, let id = occurrenceID else { return }
            session = nil
            occurrenceID = nil
            if schedulingID == id {
                schedulingError = error.map { self.schedulingFailure($0) }
                    ?? AlarmError.message("watchOS rejected the haptic alarm (reason \(reason.rawValue)).")
                return
            }
            guard let coordinator else { return }
            if coordinator.snapshot.dismissedIDs.contains(id) {
                await coordinator.dismiss(id)
                return
            }
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

