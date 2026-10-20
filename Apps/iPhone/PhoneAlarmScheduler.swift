// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import AlarmKit
import AppIntents
import SwiftUI

struct BeanAlarmMetadata: AlarmMetadata {
    var occurrenceID: String
}

@MainActor final class PhoneAlarmScheduler: AlarmScheduling {
    func authorize() async throws {
        guard try await AlarmManager.shared.requestAuthorization() == .authorized else {
            throw AlarmError.message("Allow alarms in iPhone Settings to enable the audible fallback.")
        }
    }

    func schedule(_ occurrence: AlarmOccurrence) async throws {
        guard AlarmManager.shared.authorizationState == .authorized else {
            throw AlarmError.message("Open Alarm Beans on iPhone and allow alarms first.")
        }
        let alert = AlarmPresentation.Alert(
            title: "Time to wake up",
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: BeanAlarmMetadata(occurrenceID: occurrence.id.uuidString),
            tintColor: Color(red: 0.48, green: 0.78, blue: 0.46)
        )
        let config = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(occurrence.fallbackTime),
            attributes: attributes,
            stopIntent: StopBeanAlarmIntent(id: occurrence.id.uuidString),
            sound: .default
        )
        _ = try await AlarmManager.shared.schedule(id: occurrence.id, configuration: config)
    }

    func cancel(_ id: UUID) async throws {
        if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
            try AlarmManager.shared.cancel(id: id)
        }
    }

    func scheduledIDs() async throws -> Set<UUID>? {
        Set(try AlarmManager.shared.alarms.map(\.id))
    }
}

struct StopBeanAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Alarm Beans"
    static var description = IntentDescription("Stops this wake-up on both paired devices.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alarm identifier") var id: String

    init() {}
    init(id: String) { self.id = id }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: id) else { throw AlarmError.invalidOccurrence }
        await PhoneRuntime.shared.coordinator.dismiss(uuid)
        return .result()
    }
}

