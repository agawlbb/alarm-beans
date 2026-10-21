// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Waits for a system scheduler's asynchronous state change without treating
/// a still-pending request as rejection or presenting it as an armed alarm.
@MainActor public enum SchedulingConfirmation {
    public static func wait(timeout: Duration = .seconds(10),
                            pollInterval: Duration = .milliseconds(50),
                            isConfirmed: () throws -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            if try isConfirmed() { return }
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else {
                throw AlarmError.message("The Watch did not confirm alarm scheduling in time. Keep the app open and try again.")
            }
            try await Task.sleep(for: min(pollInterval, remaining))
        }
    }
}
