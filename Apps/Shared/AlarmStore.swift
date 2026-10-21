// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import Foundation

@MainActor final class AlarmStore: AlarmPersistence {
    static var groupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "AlarmBeansAppGroup") as? String
            ?? "group.com.agawlbb.alarmbeans"
    }

    private let url: URL

    init() throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupIdentifier
        ) else { throw AlarmError.message("Alarm Beans shared storage is unavailable. Check App Group signing.") }
        url = container.appendingPathComponent("alarm-state.json")
    }

    func load() throws -> AlarmSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return AlarmSnapshot() }
        let snapshot = try JSONDecoder().decode(AlarmSnapshot.self, from: Data(contentsOf: url))
        try snapshot.settings.value.validate()
        if let occurrence = snapshot.record?.occurrence {
            try occurrence.settings.validate()
            guard occurrence.wakeTime.timeIntervalSince1970.isFinite else { throw AlarmError.invalidOccurrence }
        }
        return snapshot
    }

    func save(_ snapshot: AlarmSnapshot) throws {
        try JSONEncoder().encode(snapshot).write(
            to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}

