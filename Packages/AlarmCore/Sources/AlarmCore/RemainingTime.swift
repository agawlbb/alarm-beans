// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct RemainingTime: Equatable, Sendable {
    public let hours: Int
    public let minutes: Int
    public let isDue: Bool

    public init(until target: Date, now: Date) {
        let interval = target.timeIntervalSince(now)
        isDue = interval <= 0
        let total = interval > 0 ? Int(ceil(interval / 60)) : 0
        hours = total / 60
        minutes = total % 60
    }

    public var text: String {
        if isDue { return "Due now" }
        let hourUnit = hours == 1 ? "hour" : "hours"
        let minuteUnit = minutes == 1 ? "minute" : "minutes"
        return "in \(hours) \(hourUnit) \(minutes) \(minuteUnit)"
    }
}

