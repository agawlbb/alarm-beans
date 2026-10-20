// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import Foundation

@MainActor func makeStore() -> any AlarmPersistence {
    do { return try AlarmStore() }
    catch { return UnavailableStore(error: error) }
}

@MainActor private final class UnavailableStore: AlarmPersistence {
    let error: Error
    init(error: Error) { self.error = error }
    func load() throws -> AlarmSnapshot { throw error }
    func save(_ snapshot: AlarmSnapshot) throws { throw error }
}
