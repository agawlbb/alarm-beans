// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import AlarmKit
import SwiftUI
import Observation
import UIKit

@MainActor @Observable final class PhoneRuntime {
    static let shared = PhoneRuntime()
    let scheduler = PhoneAlarmScheduler()
    let link = ConnectivityLink()
    let coordinator: PairCoordinator
    private var observation: Task<Void, Never>?
    var authorizationState = AlarmManager.shared.authorizationState
    var permissionError: String?
    private var requestingPermission = false

    func checkAuthorization() async {
        authorizationState = AlarmManager.shared.authorizationState
        if authorizationState == .authorized { permissionError = nil }
        guard UIApplication.shared.applicationState == .active,
              authorizationState == .notDetermined, !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        do {
            authorizationState = try await AlarmManager.shared.requestAuthorization()
            permissionError = nil
        } catch {
            permissionError = error.localizedDescription
            authorizationState = AlarmManager.shared.authorizationState
        }
    }

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
            AlarmHomeView(coordinator: runtime.coordinator,
                          phoneAlarmsDenied: runtime.authorizationState == .denied,
                          permissionError: runtime.permissionError)
            .task {
                await runtime.coordinator.synchronize()
                await runtime.checkAuthorization()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await runtime.coordinator.synchronize()
                        await runtime.checkAuthorization()
                    }
                }
            }
        }
    }
}

