// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import AlarmKit
import SwiftUI

@MainActor final class PhoneRuntime {
    static let shared = PhoneRuntime()
    let scheduler = PhoneAlarmScheduler()
    let link = ConnectivityLink()
    let coordinator: PairCoordinator
    private var observation: Task<Void, Never>?

    private init() {
        coordinator = PairCoordinator(role: .phone, scheduler: scheduler, link: link, persistence: makeStore())
        link.activate()
        observation = Task { [weak self] in
            for await _ in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                await coordinator.reconcilePhone()
            }
        }
    }
}

@main struct AlarmBeansApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let runtime = PhoneRuntime.shared

    var body: some Scene {
        WindowGroup {
            AlarmHomeView(coordinator: runtime.coordinator, authorize: {
                try await runtime.scheduler.authorize()
            })
            .task { await runtime.coordinator.synchronize() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await runtime.coordinator.synchronize() } }
            }
        }
    }
}

