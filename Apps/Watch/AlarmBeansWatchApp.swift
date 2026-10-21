// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import SwiftUI
import WatchKit
import WidgetKit

@MainActor final class WatchRuntime {
    static let shared = WatchRuntime()
    let scheduler = WatchAlarmScheduler()
    let link = ConnectivityLink()
    let coordinator: PairCoordinator

    private init() {
        coordinator = PairCoordinator(role: .watch, scheduler: scheduler, link: link, persistence: makeStore())
        scheduler.coordinator = coordinator
        coordinator.onChange = { [weak scheduler] in
            scheduler?.refreshAlert()
            WidgetCenter.shared.reloadTimelines(ofKind: "AlarmBeansWakeTime")
        }
        link.activate()
    }
}

@MainActor final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        WatchRuntime.shared.scheduler.restore(extendedRuntimeSession)
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask {
                WatchRuntime.shared.link.handle(connectivity)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

@main struct AlarmBeansWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationID = UUID()
    private let runtime = WatchRuntime.shared

    var body: some Scene {
        WindowGroup {
            AlarmHomeView(coordinator: runtime.coordinator)
                .id(navigationID)
                .onOpenURL { url in
                    guard url.scheme == "alarmbeans", url.host == "alarm" else { return }
                    // Reset any settings navigation so every complication tap reaches the alarm screen.
                    navigationID = UUID()
                }
                .task { await runtime.coordinator.synchronize() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await runtime.coordinator.synchronize() } }
                    if phase == .background { WidgetCenter.shared.reloadTimelines(ofKind: "AlarmBeansWakeTime") }
                }
        }
    }
}

