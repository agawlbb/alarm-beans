// SPDX-License-Identifier: MPL-2.0
import Foundation

extension AlarmSettings {
    // Dial fields wrap independently; a 12-hour dial preserves the chosen AM/PM.
    public mutating func setDialHour(_ value: Int, uses24Hour: Bool) {
        let count = uses24Hour ? 24 : 12
        let wrapped = ((value % count) + count) % count
        hour = wrapped + (uses24Hour ? 0 : (hour / 12) * 12)
    }

    public mutating func setDialMinute(_ value: Int) {
        minute = ((value % 60) + 60) % 60
    }
}
