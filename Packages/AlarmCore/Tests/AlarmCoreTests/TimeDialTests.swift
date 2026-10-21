// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import AlarmCore

@Test func twelveHourDialWrapsBothWaysWithoutChangingPeriod() {
    var settings = AlarmSettings(hour: 0, minute: 59)
    settings.setDialHour(1, uses24Hour: false)
    #expect(settings.hour == 1) // 12 AM -> 1 AM
    settings.setDialHour(0, uses24Hour: false)
    #expect(settings.hour == 0) // 1 AM -> 12 AM
    settings.hour = 12
    settings.setDialHour(13, uses24Hour: false)
    #expect(settings.hour == 13) // 12 PM -> 1 PM
    settings.setDialHour(-1, uses24Hour: false)
    #expect(settings.hour == 23)
    #expect(settings.minute == 59)
}

@Test func minuteDialWrapsWithoutCarryingIntoHour() {
    var settings = AlarmSettings(hour: 23, minute: 59)
    settings.setDialMinute(60)
    #expect(settings.minute == 0)
    #expect(settings.hour == 23)
    settings.setDialMinute(-1)
    #expect(settings.minute == 59)
    #expect(settings.hour == 23)
}

@Test func twentyFourHourDialWrapsAtMidnight() {
    var settings = AlarmSettings(hour: 23, minute: 30)
    settings.setDialHour(24, uses24Hour: true)
    #expect(settings.hour == 0)
    settings.setDialHour(-1, uses24Hour: true)
    #expect(settings.hour == 23)
    #expect(settings.minute == 30)
}
