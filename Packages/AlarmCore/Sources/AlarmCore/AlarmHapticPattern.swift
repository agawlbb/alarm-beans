// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum AlarmHapticPattern: String, Codable, CaseIterable, Hashable, Sendable {
    case notification, click, retry, success, start

    public var title: String {
        switch self {
        case .notification: "Notification"
        case .click: "Click"
        case .retry: "Retry"
        case .success: "Success"
        case .start: "Start"
        }
    }
}
