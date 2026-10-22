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
    var occurrences: [AlarmOccurrence] = []
    func schedule(_ occurrence: AlarmOccurrence) async throws {
        occurrences.append(occurrence)
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
    var beforeRequest: ((AlarmMessage) async -> Void)?
    var afterRequest: ((AlarmMessage) async -> Void)?
    func request(_ message: AlarmMessage) async throws -> AlarmReply {
        guard !offline, let handler = peer?.onMessage else { throw AlarmError.unavailable }
        await beforeRequest?(message)
        let reply = await handler(message)
        await afterRequest?(message)
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

@Test @MainActor func armCapturesDisplayedSettingsForBothSchedulers() async {
    let pair = Pair()
    let settings = AlarmSettings(hour: 9, minute: 17, fallbackMinutes: 8, hapticSeconds: 13)
    #expect(pair.watch.updateSettings(settings))
    let displayed = pair.watch.displayedSettings
    await pair.watch.arm()
    #expect(pair.watchScheduler.occurrences.first?.settings == displayed)
    #expect(pair.phoneScheduler.occurrences.first?.settings == displayed)
    #expect(pair.phone.displayedSettings == displayed)
    #expect(pair.watch.displayedSettings == displayed)
    #expect(pair.phone.snapshot.record?.occurrence == pair.watch.snapshot.record?.occurrence)
}

@Test @MainActor func everySettingsPathRejectsDuringPreparingAndArmed() async {
    let pair = Pair()
    let original = pair.watch.displayedSettings
    let edits = [AlarmSettings(hour: 11), AlarmSettings(minute: 42),
                 AlarmSettings(fallbackMinutes: 15), AlarmSettings(hapticSeconds: 27)]
    func assertLocked() async {
        for edit in edits {
            #expect(!pair.watch.updateSettings(edit))
            #expect(!pair.phone.updateSettings(edit))
            #expect((try? await pair.phone.applyExternalSettings(edit)) == false)
            for coordinator in [pair.phone, pair.watch] {
                let update = SettingsUpdate(value: edit, timestamp: .distantFuture, epoch: coordinator.snapshot.settings.epoch)
                let reply = await coordinator.receive(AlarmMessage(.settings, settings: update))
                #expect(!reply.success)
                #expect(coordinator.displayedSettings == original)
            }
        }
    }
    pair.phoneScheduler.onSchedule = { await assertLocked() }
    await pair.watch.arm()
    #expect(pair.watch.confirmedArmed)
    await assertLocked()
    #expect(pair.phoneScheduler.occurrences.first?.settings == original)
    #expect(pair.watchScheduler.occurrences.first?.settings == original)
}

@Test @MainActor func delayedSettingsCannotCrossArmDismissFence() async {
    let pair = Pair()
    let oldEpoch = pair.watch.snapshot.settings.epoch
    let stale = SettingsUpdate(value: AlarmSettings(hour: 13, minute: 51), timestamp: .distantFuture, epoch: oldEpoch)
    await pair.watch.arm()
    #expect(pair.watch.snapshot.settings.epoch != oldEpoch)
    #expect(!(await pair.watch.receive(AlarmMessage(.settings, settings: stale))).success)
    await pair.watch.dismissCurrent()
    #expect(pair.watch.settingsEditable)
    #expect(pair.phone.settingsEditable)
    for coordinator in [pair.phone, pair.watch] {
        #expect(!(await coordinator.receive(AlarmMessage(.settings, settings: stale))).success)
        #expect(coordinator.displayedSettings == AlarmSettings())
    }
}

@Test @MainActor func externalEditAcceptedBeforeArmIsTheScheduledDisplay() async throws {
    let pair = Pair()
    let wanted = AlarmSettings(hour: 10, minute: 28, fallbackMinutes: 12, hapticSeconds: 9)
    pair.phoneLink.afterRequest = { message in
        if message.kind == .settings { await pair.watch.arm() }
    }
    #expect(try await pair.phone.applyExternalSettings(wanted))
    #expect(pair.watch.confirmedArmed)
    for coordinator in [pair.phone, pair.watch] { #expect(coordinator.displayedSettings == wanted) }
    #expect(pair.phoneScheduler.occurrences.first?.settings == wanted)
    #expect(pair.watchScheduler.occurrences.first?.settings == wanted)
}

@Test @MainActor func armWinningTheExternalEditRaceRejectsThatEdit() async throws {
    let pair = Pair()
    pair.phoneLink.beforeRequest = { message in
        if message.kind == .settings { await pair.watch.arm() }
    }
    #expect(try await pair.phone.applyExternalSettings(AlarmSettings(hour: 15)) == false)
    #expect(pair.watch.confirmedArmed)
    #expect(pair.watch.displayedSettings == AlarmSettings())
    #expect(pair.phone.displayedSettings == AlarmSettings())
    await pair.watch.dismissCurrent()
    #expect(pair.watch.displayedSettings == AlarmSettings())
}

@Test @MainActor func watchOpeningRequestsPhoneBridgeAndOfflineKeepsSettings() async {
    let pair = Pair()
    var bridgeCalls = 0
    pair.phone.onAppOpenSync = { bridgeCalls += 1 }
    await pair.watch.synchronize()
    #expect(bridgeCalls == 1)
    let before = pair.watch.displayedSettings
    pair.watchLink.offline = true
    await pair.watch.synchronize()
    #expect(bridgeCalls == 1)
    #expect(pair.watch.displayedSettings == before)
}

@MainActor private final class HAJournal: HomeAssistantJournal {
    var receipts: [HomeAssistantReceipt] = []
    var fail = false
    func save(_ value: [HomeAssistantReceipt]) throws {
        if fail { throw AlarmError.unavailable }
        receipts = value
    }
}

@MainActor private final class HATransport: HomeAssistantTransport {
    var commands: [HomeAssistantRequest] = []
    var fail = false
    var reports: [HomeAssistantReport] = []
    func exchange(_ report: HomeAssistantReport) async throws -> [HomeAssistantRequest] {
        if fail { throw AlarmError.unavailable }
        reports.append(report)
        let result = commands
        commands = []
        return result
    }
}

@Test @MainActor func appOpenBridgeAcknowledgesOnlyWatchAcceptedValues() async throws {
    let pair = Pair()
    let journal = HAJournal()
    let transport = HATransport()
    transport.commands = [HomeAssistantRequest(field: "wake_time", value: "09:43"),
                          HomeAssistantRequest(field: "haptic_interval", value: "14"),
                          HomeAssistantRequest(field: "iphone_offset", value: "11")]
    try await HomeAssistantSync(coordinator: pair.phone, transport: transport, journal: journal).synchronize()
    #expect(pair.phone.displayedSettings.hour == 9)
    #expect(pair.watch.displayedSettings.minute == 43)
    #expect(pair.phone.displayedSettings.hapticSeconds == 14)
    #expect(pair.watch.displayedSettings.fallbackMinutes == 11)
    #expect(transport.reports.last?.receipts.allSatisfy(\.accepted) == true)
    #expect(transport.reports.last?.values == HomeAssistantValues(pair.watch.displayedSettings))
    #expect(journal.receipts.isEmpty)
}

@Test @MainActor func failedBridgeAndJournalLeaveDisplayedSettingsAlone() async {
    let pair = Pair()
    let journal = HAJournal()
    let transport = HATransport()
    transport.fail = true
    do { try await HomeAssistantSync(coordinator: pair.phone, transport: transport, journal: journal).synchronize(); Issue.record("Expected network failure") }
    catch {}
    #expect(pair.phone.displayedSettings == AlarmSettings())
    transport.fail = false
    journal.fail = true
    transport.commands = [HomeAssistantRequest(field: "wake_time", value: "16:30")]
    do { try await HomeAssistantSync(coordinator: pair.phone, transport: transport, journal: journal).synchronize(); Issue.record("Expected journal failure") }
    catch {}
    #expect(pair.watch.displayedSettings == AlarmSettings())
    #expect(pair.phone.displayedSettings == AlarmSettings())
}

@Test @MainActor func lockedHARequestsAreDiscardedAndNotReplayedAfterDismissal() async throws {
    let pair = Pair()
    await pair.watch.arm()
    let journal = HAJournal()
    let transport = HATransport()
    transport.commands = [HomeAssistantRequest(field: "wake_time", value: "20:50")]
    let bridge = HomeAssistantSync(coordinator: pair.phone, transport: transport, journal: journal)
    try await bridge.synchronize()
    #expect(transport.reports.last?.receipts.first?.accepted == false)
    await pair.watch.dismissCurrent()
    try await bridge.synchronize()
    #expect(pair.phone.displayedSettings == AlarmSettings())
    #expect(pair.watch.displayedSettings == AlarmSettings())
}

@Test func pairingRequiresHTTPSOriginAndOpaqueToken() throws {
    let token = String(repeating: "a", count: 43)
    for url in ["http://ha.local", "https://name:password@ha.local", "https://ha.local/path", "https://ha.local?x=1"] {
        let data = try JSONEncoder().encode(["url": url, "token": token])
        let pairing = try JSONDecoder().decode(HomeAssistantPairing.self, from: data)
        #expect(throws: (any Error).self) { try pairing.validate() }
    }
    let data = try JSONEncoder().encode(["url": "https://ha.example:8123", "token": token])
    try JSONDecoder().decode(HomeAssistantPairing.self, from: data).validate()
}

@Test @MainActor func unchangedFailureStateDoesNotCreateSyncFeedbackLoop() async {
    let pair = Pair()
    await pair.watch.arm()
    pair.watch.reportRuntimeFailure(pair.watch.snapshot.record!.occurrence.id, detail: "Session expired")
    var changes = 0
    pair.phone.onChange = { changes += 1 }
    await pair.phone.synchronize()
    let first = changes
    #expect(first > 0)
    await pair.phone.synchronize()
    #expect(changes == first)
}

@Test @MainActor func rejectedCurrentEpochEditCannotApplyAfterDismissalOrRelaunch() async throws {
    let pair = Pair()
    await pair.watch.arm()
    let rejected = SettingsUpdate(value: AlarmSettings(hour: 18), timestamp: .distantFuture,
                                  epoch: pair.watch.snapshot.settings.epoch)
    #expect(!(await pair.watch.receive(AlarmMessage(.settings, settings: rejected))).success)
    await pair.watch.dismissCurrent()
    pair.watchStore.state = try JSONDecoder().decode(AlarmSnapshot.self, from: JSONEncoder().encode(pair.watchStore.state))
    let restored = PairCoordinator(role: .watch, scheduler: FakeScheduler(), link: FakeLink(), persistence: pair.watchStore)
    #expect(restored.settingsEditable)
    #expect(!(await restored.receive(AlarmMessage(.settings, settings: rejected))).success)
    #expect(restored.displayedSettings == AlarmSettings())
}
