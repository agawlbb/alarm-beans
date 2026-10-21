// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import AlarmCore

@MainActor private final class MemoryStore: AlarmPersistence {
    var state = AlarmSnapshot()
    var saveFails = false
    func load() throws -> AlarmSnapshot { state }
    func save(_ snapshot: AlarmSnapshot) throws {
        if saveFails { throw AlarmError.message("Storage unavailable") }
        state = snapshot
    }
}

@MainActor private final class FakeScheduler: AlarmScheduling {
    var ids: Set<UUID> = []
    var scheduleFails = false
    var cancelFails = false
    var onSchedule: (() async -> Void)?
    func schedule(_ occurrence: AlarmOccurrence) async throws {
        if scheduleFails { throw AlarmError.unavailable }
        ids.insert(occurrence.id)
        await onSchedule?()
    }
    func cancel(_ id: UUID) async throws {
        if cancelFails { throw AlarmError.unavailable }
        ids.remove(id)
    }
    func scheduledIDs() async throws -> Set<UUID>? { ids }
}

@MainActor private final class FakeLink: AlarmLink {
    var onMessage: ((AlarmMessage) async -> AlarmReply)?
    var onReconnect: (() async -> Void)?
    var peer: FakeLink?
    var offline = false
    var dropConfirmationReply = false
    var dropCancellationReply = false
    var queued: [AlarmMessage] = []
    func request(_ message: AlarmMessage) async throws -> AlarmReply {
        guard !offline, let handler = peer?.onMessage else { throw AlarmError.unavailable }
        let reply = await handler(message)
        if dropConfirmationReply && message.kind == .confirmWatch { throw AlarmError.timedOut }
        if dropCancellationReply && message.kind == .cancel {
            _ = await onMessage?(AlarmMessage(.cancellationAcknowledged, id: message.id))
            throw AlarmError.timedOut
        }
        return reply
    }
    func enqueue(_ message: AlarmMessage) { queued.append(message) }
    func deliverQueued() async {
        let messages = queued
        queued.removeAll()
        for message in messages { _ = await peer?.onMessage?(message) }
    }
}

@MainActor private struct Pair {
    let phoneScheduler = FakeScheduler()
    let watchScheduler = FakeScheduler()
    let phoneLink = FakeLink()
    let watchLink = FakeLink()
    let phoneStore = MemoryStore()
    let watchStore = MemoryStore()
    let phone: PairCoordinator
    let watch: PairCoordinator

    init() {
        phone = PairCoordinator(role: .phone, scheduler: phoneScheduler, link: phoneLink, persistence: phoneStore)
        watch = PairCoordinator(role: .watch, scheduler: watchScheduler, link: watchLink, persistence: watchStore)
        phoneLink.peer = watchLink
        watchLink.peer = phoneLink
    }
}

@Test @MainActor func successfulArmRequiresBothSchedulers() async {
    let pair = Pair()
    await pair.watch.arm()
    #expect(pair.watch.snapshot.record?.phase == .armed)
    #expect(pair.phone.snapshot.record?.phase == .armed)
    #expect(pair.watchScheduler.ids == pair.phoneScheduler.ids)
    #expect(pair.watchScheduler.ids.count == 1)
}

@Test @MainActor func watchSchedulingFailureRollsBackPhone() async {
    let pair = Pair()
    pair.watchScheduler.scheduleFails = true
    await pair.watch.arm()
    #expect(pair.phoneScheduler.ids.isEmpty)
    #expect(pair.watchScheduler.ids.isEmpty)
    #expect(pair.watch.snapshot.record?.phase == .failed)
    #expect(pair.watch.issue != nil)
}

@Test @MainActor func phoneFailureNeverSchedulesWatch() async {
    let pair = Pair()
    pair.phoneScheduler.scheduleFails = true
    await pair.watch.arm()
    #expect(pair.watchScheduler.ids.isEmpty)
    #expect(pair.watch.snapshot.record?.phase != .armed)
}

@Test @MainActor func lostFinalAcknowledgmentRollsBackBoth() async {
    let pair = Pair()
    pair.watchLink.dropConfirmationReply = true
    await pair.watch.arm()
    #expect(pair.phoneScheduler.ids.isEmpty)
    #expect(pair.watchScheduler.ids.isEmpty)
    #expect(pair.watch.snapshot.record?.phase != .armed)
}

@Test @MainActor func offlineDismissalKeepsPhoneUntilReconnect() async {
    let pair = Pair()
    await pair.watch.arm()
    pair.watchLink.offline = true
    await pair.watch.dismissCurrent()
    #expect(pair.watchScheduler.ids.isEmpty)
    #expect(!pair.phoneScheduler.ids.isEmpty)
    #expect(pair.watch.snapshot.record?.phase == .cancellationPending)
    #expect(pair.watch.snapshot.record?.complicationTime(at: Date()) == nil)
    pair.watchLink.offline = false
    await pair.watch.synchronize()
    #expect(pair.phoneScheduler.ids.isEmpty)
    #expect(pair.watch.snapshot.pendingCancellations.isEmpty)
    #expect(pair.watch.issue == nil)
}

@Test @MainActor func phoneDismissalStopsWatch() async {
    let pair = Pair()
    await pair.watch.arm()
    await pair.phone.dismissCurrent()
    #expect(pair.phoneScheduler.ids.isEmpty)
    #expect(pair.watchScheduler.ids.isEmpty)
    #expect(pair.phone.snapshot.record?.phase == .dismissed)
    #expect(pair.watch.snapshot.record?.phase == .dismissed)
}

@Test @MainActor func stopDuringPhoneSchedulingCannotResurrectAlarm() async throws {
    let pair = Pair()
    pair.phoneScheduler.onSchedule = {
        await pair.phone.dismissCurrent()
    }
    await pair.watch.arm()
    #expect(pair.phoneScheduler.ids.isEmpty)
    #expect(pair.watchScheduler.ids.isEmpty)
    #expect(pair.watch.snapshot.record?.phase != .armed)
    let alarm = try #require(pair.phone.snapshot.record?.occurrence)
    let late = await pair.phone.receive(AlarmMessage(.prepareFallback, occurrence: alarm))
    #expect(!late.success)
}

@Test @MainActor func oldQueuedCancelDoesNotStopNewPair() async {
    let pair = Pair()
    await pair.watch.arm()
    await pair.watch.dismissCurrent()
    await pair.watch.arm()
    let currentID = pair.watch.snapshot.record?.occurrence.id
    await pair.watchLink.deliverQueued()
    #expect(pair.phone.snapshot.record?.occurrence.id == currentID)
    #expect(pair.phone.snapshot.record?.phase == .armed)
    #expect(pair.phoneScheduler.ids.count == 1)
}

@Test @MainActor func failureRetainsFallbackAndBlocksAnotherArm() async {
    let pair = Pair()
    await pair.watch.arm()
    guard let id = pair.watch.snapshot.record?.occurrence.id else { Issue.record("Missing occurrence"); return }
    pair.watch.reportRuntimeFailure(id, detail: "Session expired.")
    #expect(pair.watch.snapshot.record?.blocksNewAlarm == true)
    #expect(pair.phoneScheduler.ids.contains(id))
}

@Test @MainActor func diskFailureStillStopsLocalHaptics() async {
    let pair = Pair()
    await pair.watch.arm()
    pair.watchStore.saveFails = true
    await pair.watch.dismissCurrent()
    #expect(pair.watchScheduler.ids.isEmpty)
    #expect(pair.watch.snapshot.record?.phase == .cancellationPending)
    #expect(pair.watch.issue != nil)
}

@Test @MainActor func pendingLocalCancelCannotBeClearedByRemoteAcknowledgment() async {
    let pair = Pair()
    await pair.watch.arm()
    guard let id = pair.watch.snapshot.record?.occurrence.id else { Issue.record("Missing occurrence"); return }
    pair.watchScheduler.cancelFails = true
    await pair.watch.dismissCurrent()
    let reply = await pair.watch.receive(AlarmMessage(.cancellationAcknowledged, id: id))
    #expect(!reply.success)
    #expect(pair.watch.snapshot.pendingCancellations.contains(id))
    #expect(pair.watch.snapshot.record?.phase == .cancellationPending)
}

@Test @MainActor func durableAcknowledgmentWinsOverLostLiveReply() async {
    let pair = Pair()
    await pair.watch.arm()
    pair.watchLink.dropCancellationReply = true
    await pair.watch.dismissCurrent()
    #expect(pair.watch.snapshot.pendingCancellations.isEmpty)
    #expect(pair.watch.snapshot.record?.phase == .dismissed)
    #expect(pair.watch.issue == nil)
}

@Test @MainActor func patternAndTimingReachBothScheduledOccurrences() async {
    let pair = Pair()
    pair.watch.updateSettings(AlarmSettings(fallbackMinutes: 7, hapticSeconds: 3, hapticPattern: .retry))
    await pair.watch.arm()
    #expect(pair.phone.snapshot.record?.occurrence.settings.hapticPattern == .retry)
    #expect(pair.watch.snapshot.record?.occurrence.settings.hapticPattern == .retry)
    #expect(pair.phone.snapshot.record?.occurrence.settings.fallbackMinutes == 7)
    #expect(pair.phone.snapshot.record?.occurrence.settings.hapticSeconds == 3)
}

@Test @MainActor func phoneStopKeepsDurableWatchCancellationWhenOffline() async {
    let pair = Pair()
    await pair.watch.arm()
    let id = pair.phone.snapshot.record!.occurrence.id
    pair.phoneLink.offline = true
    await pair.phone.dismissCurrent()
    #expect(pair.phoneScheduler.ids.isEmpty)
    #expect(pair.watchScheduler.ids.contains(id))
    #expect(pair.phone.snapshot.pendingCancellations.contains(id))
    #expect(pair.phone.snapshot.dismissedIDs.contains(id))
    pair.phoneLink.offline = false
    await pair.phone.synchronize()
    #expect(pair.watchScheduler.ids.isEmpty)
    #expect(pair.phone.snapshot.pendingCancellations.isEmpty)
}
