// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum TimeDialField: Equatable, Sendable { case hour, minute }

/// A single Crown input owner. Selection invalidates queued callbacks and partial turns.
public struct CrownTimeDial: Sendable {
    public private(set) var field: TimeDialField = .hour
    public private(set) var generation = 0
    public private(set) var position: Double = 0
    private var remainder: Double = 0
    public static let limit: Double = 1_000_000

    public init() {}

    public mutating func select(_ field: TimeDialField) {
        self.field = field
        generation += 1
        position = 0
        remainder = 0
    }

    @discardableResult
    public mutating func move(to value: Double, generation: Int,
                              settings: inout AlarmSettings, uses24Hour: Bool) -> Bool {
        guard generation == self.generation, value.isFinite, abs(value) <= Self.limit else { return false }
        var delta = value - position
        let period = Self.limit * 2 + 1
        if delta > Self.limit { delta -= period }
        if delta < -Self.limit { delta += period }
        position = value
        remainder += delta
        let units: Double = field == .hour ? 2 : 1
        let steps = Int(remainder / units)
        guard steps != 0 else { return false }
        remainder -= Double(steps) * units
        let previous = settings
        if field == .hour {
            settings.setDialHour(settings.hour + steps, uses24Hour: uses24Hour)
        } else {
            settings.setDialMinute(settings.minute + steps)
        }
        return settings != previous
    }
}
