// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import AlarmCore

@Test @MainActor func delayedSystemSchedulingIsNotRejected() async throws {
    var confirmed = false
    let update = Task { @MainActor in
        try await Task.sleep(for: .milliseconds(30))
        confirmed = true
    }
    defer { update.cancel() }
    try await SchedulingConfirmation.wait(timeout: .seconds(2), pollInterval: .milliseconds(5)) { confirmed }
    #expect(confirmed)
}

@Test @MainActor func systemRejectionPreservesItsError() async {
    var error: AlarmError?
    let update = Task { @MainActor in
        try await Task.sleep(for: .milliseconds(10))
        error = .message("System rejected scheduling: diagnostic 17")
    }
    defer { update.cancel() }
    do {
        try await SchedulingConfirmation.wait(timeout: .seconds(2), pollInterval: .milliseconds(5)) {
            if let error { throw error }
            return false
        }
        Issue.record("Rejected scheduling must not succeed")
    } catch {
        #expect(error.localizedDescription == "System rejected scheduling: diagnostic 17")
    }
}

@Test @MainActor func unconfirmedSchedulingTimesOut() async {
    do {
        try await SchedulingConfirmation.wait(timeout: .milliseconds(20), pollInterval: .milliseconds(5)) { false }
        Issue.record("An unconfirmed schedule must not succeed")
    } catch {
        #expect(error.localizedDescription.contains("did not confirm alarm scheduling in time"))
    }
}

@Test @MainActor func cancellationStopsSchedulingWait() async {
    let task = Task { @MainActor in
        try await SchedulingConfirmation.wait { false }
    }
    task.cancel()
    do {
        try await task.value
        Issue.record("A canceled schedule must not succeed")
    } catch {
        #expect(error is CancellationError)
    }
}
