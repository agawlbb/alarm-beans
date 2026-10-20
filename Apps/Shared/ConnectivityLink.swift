// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import Foundation
@preconcurrency import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

@MainActor final class ConnectivityLink: NSObject, AlarmLink, WCSessionDelegate {
    var onMessage: ((AlarmMessage) async -> AlarmReply)?
    var onReconnect: (() async -> Void)?
    private let session = WCSession.default
    private var handlingCount = 0
    #if os(watchOS)
    private var backgroundTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    #endif

    override init() {
        super.init()
        session.delegate = self
    }

    func activate() { session.activate() }

    func request(_ message: AlarmMessage) async throws -> AlarmReply {
        guard session.activationState == .activated else { throw AlarmError.unavailable }
        let data = try JSONEncoder().encode(message)
        return try await withCheckedThrowingContinuation { continuation in
            let pending = PendingReply(continuation)
            session.sendMessage(["alarmBeans": data], replyHandler: { payload in
                let replyData = payload["alarmBeans"] as? Data
                Task { @MainActor in
                    do {
                        guard let replyData else { throw AlarmError.unavailable }
                        pending.finish(.success(try JSONDecoder().decode(AlarmReply.self, from: replyData)))
                    } catch { pending.finish(.failure(error)) }
                }
            }, errorHandler: { error in
                Task { @MainActor in pending.finish(.failure(error)) }
            })
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                pending.finish(.failure(AlarmError.timedOut))
            }
        }
    }

    func enqueue(_ message: AlarmMessage) {
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(message) else { return }
        // Settings coalesce; cancellations use a durable ordered transfer.
        if message.kind == .settings {
            try? session.updateApplicationContext(["alarmBeans": data])
        } else {
            session.transferUserInfo(["alarmBeans": data])
        }
    }

    private func deliver(_ data: Data?) async -> AlarmReply {
        handlingCount += 1
        defer {
            handlingCount -= 1
            finishBackgroundTasks()
        }
        guard let data, let message = try? JSONDecoder().decode(AlarmMessage.self, from: data),
              let onMessage else { return AlarmReply(success: false, detail: "Invalid message") }
        return await onMessage(message)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor [weak self] in
            if activationState == .activated { await self?.onReconnect?() }
            self?.finishBackgroundTasks()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in await self?.onReconnect?() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let data = message["alarmBeans"] as? Data
        Task { @MainActor [weak self] in
            let reply = await self?.deliver(data) ?? AlarmReply(success: false, detail: "App unavailable")
            let encoded = (try? JSONEncoder().encode(reply)) ?? Data()
            replyHandler(["alarmBeans": encoded])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let data = userInfo["alarmBeans"] as? Data
        Task { @MainActor [weak self] in _ = await self?.deliver(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["alarmBeans"] as? Data
        Task { @MainActor [weak self] in _ = await self?.deliver(data) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    #if os(watchOS)
    func handle(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        backgroundTasks.append(task)
        finishBackgroundTasks()
    }
    #endif

    private func finishBackgroundTasks() {
        #if os(watchOS)
        guard handlingCount == 0, session.activationState == .activated, !session.hasContentPending else { return }
        backgroundTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
        backgroundTasks.removeAll()
        #endif
    }
}

@MainActor private final class PendingReply {
    private var continuation: CheckedContinuation<AlarmReply, Error>?
    init(_ continuation: CheckedContinuation<AlarmReply, Error>) { self.continuation = continuation }
    func finish(_ result: Result<AlarmReply, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

