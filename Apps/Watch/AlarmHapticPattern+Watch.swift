// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import WatchKit

extension AlarmHapticPattern {
    var watchHaptic: WKHapticType {
        switch self {
        case .notification: .notification
        case .click: .click
        case .retry: .retry
        case .success: .success
        case .start: .start
        }
    }
}
