// SPDX-License-Identifier: MPL-2.0
#if DEBUG
import AlarmCore
import SwiftUI
import Foundation

/// Simulator-only fixtures use the real screens without signing or a paired phone.
@MainActor struct WatchInterfaceReview: View {
    let screen: String
    @State private var coordinator = PairCoordinator(role: .watch, scheduler: ReviewScheduler(),
                                                    link: ReviewLink(), persistence: ReviewStore())
    static var requestedScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--interface-review"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    var body: some View {
        Group {
            if screen == "home" {
                WatchAlarmHomeView(coordinator: coordinator)
            } else {
                WatchAlarmSettingsView(coordinator: coordinator, initialPath: initialPath)
            }
        }
        .task {
            if screen == "pattern-changing" {
                // Exercise observable updates while the pattern screen stays pushed.
                for pattern in [AlarmHapticPattern.retry, .success, .start] {
                    try? await Task.sleep(for: .milliseconds(500))
                    var settings = coordinator.snapshot.settings.value
                    settings.hapticPattern = pattern
                    coordinator.updateSettings(settings)
                }
            }
        }
    }

    private var initialPath: [WatchSettingsScreen] {
        switch screen {
        case "pattern", "pattern-changing": [.pattern]
        case "interval": [.interval]
        case "offset": [.offset]
        default: []
        }
    }
}

@MainActor private final class ReviewStore: AlarmPersistence {
    func load() throws -> AlarmSnapshot { AlarmSnapshot() }
    func save(_ snapshot: AlarmSnapshot) throws {}
}

@MainActor private final class ReviewScheduler: AlarmScheduling {
    func schedule(_ occurrence: AlarmOccurrence) async throws {}
    func cancel(_ id: UUID) async throws {}
    func scheduledIDs() async throws -> Set<UUID>? { nil }
}

@MainActor private final class ReviewLink: AlarmLink {
    var onMessage: ((AlarmMessage) async -> AlarmReply)?
    var onReconnect: (() async -> Void)?
    func request(_ message: AlarmMessage) async throws -> AlarmReply { throw AlarmError.unavailable }
    func enqueue(_ message: AlarmMessage) {}
}
#endif
