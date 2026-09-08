import Foundation
import Testing

@testable import Nesteferge

@Suite("Departure formatting")
struct DepartureFormatterTests {

    private let oslo = TimeZone(identifier: "Europe/Oslo")!
    private let locale = Locale(identifier: "en_GB")

    private func osloDate(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = oslo
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    // MARK: - Countdown

    @Test("Under an hour renders as mm:ss")
    func countdownMinutes() {
        #expect(DepartureFormatter.countdown(seconds: 0) == "00:00")
        #expect(DepartureFormatter.countdown(seconds: 59) == "00:59")
        #expect(DepartureFormatter.countdown(seconds: 65) == "01:05")
        #expect(DepartureFormatter.countdown(seconds: 3599) == "59:59")
    }

    @Test("An hour or more renders as h:mm:ss")
    func countdownHours() {
        #expect(DepartureFormatter.countdown(seconds: 3600) == "1:00:00")
        #expect(DepartureFormatter.countdown(seconds: 3661) == "1:01:01")
        #expect(DepartureFormatter.countdown(seconds: 86_399) == "23:59:59")
    }

    @Test("Negative input clamps to zero rather than rendering a minus sign")
    func countdownNegative() {
        #expect(DepartureFormatter.countdown(seconds: -30) == "00:00")
    }

    // MARK: - Coarse countdown (CarPlay)

    @Test("Under a minute avoids showing a misleading '0 min'")
    func coarseCountdownImminent() {
        #expect(DepartureFormatter.coarseCountdown(seconds: 0) == "Under 1 min")
        #expect(DepartureFormatter.coarseCountdown(seconds: 59) == "Under 1 min")
        #expect(DepartureFormatter.coarseCountdown(seconds: -30) == "Under 1 min")
    }

    @Test("Minutes round down, so the sailing is never announced as later than it is")
    func coarseCountdownRoundsDown() {
        #expect(DepartureFormatter.coarseCountdown(seconds: 60) == "1 min")
        // 119s is 1m59s: must not round up to 2 min.
        #expect(DepartureFormatter.coarseCountdown(seconds: 119) == "1 min")
        #expect(DepartureFormatter.coarseCountdown(seconds: 3599) == "59 min")
    }

    @Test("An hour or more splits into hours and minutes")
    func coarseCountdownHours() {
        #expect(DepartureFormatter.coarseCountdown(seconds: 3600) == "1 h 0 min")
        #expect(DepartureFormatter.coarseCountdown(seconds: 3660) == "1 h 1 min")
        #expect(DepartureFormatter.coarseCountdown(seconds: 7500) == "2 h 5 min")
    }

    @Test("The coarse countdown never renders seconds")
    func coarseCountdownHasNoSeconds() {
        // Guards the CarPlay 10-second refresh rule: a seconds digit would either
        // breach it or visibly jump. Sample across a wide range of offsets.
        for seconds in stride(from: 0, through: 7200, by: 7) {
            let rendered = DepartureFormatter.coarseCountdown(seconds: seconds)
            #expect(!rendered.contains(":"), "unexpected clock formatting: \(rendered)")
        }
    }

    // MARK: - Clock

    @Test("Departure time is rendered in Oslo, not the device time zone")
    func clockUsesOslo() {
        // 2026-09-01T15:40:00+02:00
        let date = osloDate(2026, 9, 1, 15, 40)
        #expect(DepartureFormatter.clock(date, locale: locale) == "15:40")
    }

    // MARK: - Day labels

    @Test("Same Oslo calendar day is Today")
    func dayLabelToday() {
        let now = osloDate(2026, 9, 1, 9, 0)
        let departure = osloDate(2026, 9, 1, 23, 30)
        #expect(DepartureFormatter.dayLabel(departure, now: now, locale: locale) == "Today")
    }

    @Test("Next Oslo calendar day is Tomorrow")
    func dayLabelTomorrow() {
        let now = osloDate(2026, 9, 1, 23, 30)
        let departure = osloDate(2026, 9, 2, 6, 15)
        #expect(DepartureFormatter.dayLabel(departure, now: now, locale: locale) == "Tomorrow")
    }

    @Test("Beyond tomorrow falls back to the weekday name")
    func dayLabelWeekday() {
        let now = osloDate(2026, 9, 1, 12, 0)       // Tuesday
        let departure = osloDate(2026, 9, 3, 8, 0)  // Thursday
        #expect(DepartureFormatter.dayLabel(departure, now: now, locale: locale) == "Thursday")
    }

    @Test("Crossing midnight in Oslo flips Today to Tomorrow")
    func dayLabelAcrossMidnight() {
        let now = osloDate(2026, 9, 1, 23, 59)
        let justAfterMidnight = osloDate(2026, 9, 2, 0, 5)
        #expect(DepartureFormatter.dayLabel(justAfterMidnight, now: now, locale: locale) == "Tomorrow")
    }

    // MARK: - Heading

    @Test("Heading offset rounds to whole degrees")
    func headingOffset() {
        #expect(DepartureFormatter.headingOffset(degrees: 12.4) == "12° off course")
        #expect(DepartureFormatter.headingOffset(degrees: 12.6) == "13° off course")
    }
}
