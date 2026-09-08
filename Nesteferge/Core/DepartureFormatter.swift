import Foundation

/// Pure formatting helpers shared by the SwiftUI and CarPlay UIs.
/// Everything schedule-related is expressed in Europe/Oslo, matching the API.
enum DepartureFormatter {
    static let osloTimeZone = TimeZone(identifier: "Europe/Oslo") ?? .current

    private static var osloCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = osloTimeZone
        return calendar
    }()

    /// `mm:ss` under an hour, `h:mm:ss` beyond. Negative input clamps to zero.
    ///
    /// Phone only. The car uses ``coarseCountdown(seconds:)`` — see the note there.
    static func countdown(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Minute-resolution countdown for CarPlay, e.g. `12 min` or `1 t 5 min`.
    ///
    /// The CarPlay Developer Guide forbids driving task apps from refreshing data
    /// items more than once every 10 seconds, so a ticking `mm:ss` display is not
    /// permitted in the car: it would either breach the rule or visibly jump in
    /// 10-second steps. Minutes stay honest at that cadence, and are the useful
    /// unit when the question is "do I make this sailing?".
    ///
    /// Rounds down, so `59 s` reads as "under a minute" rather than "1 min".
    static func coarseCountdown(seconds: Int) -> String {
        let total = max(0, seconds)
        let totalMinutes = total / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if totalMinutes < 1 {
            return String(localized: "countdown.imminent", defaultValue: "Under 1 min")
        }
        if hours > 0 {
            return String(
                format: String(localized: "countdown.hoursMinutes", defaultValue: "%1$d h %2$d min"),
                hours,
                minutes
            )
        }
        return String(
            format: String(localized: "countdown.minutes", defaultValue: "%d min"),
            minutes
        )
    }

    /// Wall-clock departure time in Oslo, e.g. `15:40`.
    static func clock(_ date: Date, locale: Locale = .current) -> String {
        var formatStyle = Date.FormatStyle(date: .omitted, time: .shortened)
        formatStyle.locale = locale
        formatStyle.timeZone = osloTimeZone
        return date.formatted(formatStyle)
    }

    /// "Today" / "Tomorrow" / weekday name, compared in Oslo calendar days so the
    /// label stays right regardless of the device's own time zone.
    static func dayLabel(_ date: Date, now: Date = Date(), locale: Locale = .current) -> String {
        let departureDay = osloCalendar.startOfDay(for: date)
        let today = osloCalendar.startOfDay(for: now)

        if departureDay == today {
            return String(localized: "day.today", defaultValue: "Today")
        }
        if let tomorrow = osloCalendar.date(byAdding: .day, value: 1, to: today),
           departureDay == tomorrow {
            return String(localized: "day.tomorrow", defaultValue: "Tomorrow")
        }

        var formatStyle = Date.FormatStyle().weekday(.wide)
        formatStyle.locale = locale
        formatStyle.timeZone = osloTimeZone
        return date.formatted(formatStyle)
    }

    /// e.g. `1.6 km`; falls back to metres below 1 km for readability.
    static func distance(km: Double, locale: Locale = .current) -> String {
        let measurement = Measurement(value: km, unit: UnitLength.kilometers)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .road,
                numberFormatStyle: .number.precision(.fractionLength(km < 10 ? 1 : 0))
            )
            .locale(locale)
        )
    }

    /// e.g. `12° off course`.
    static func headingOffset(degrees: Double) -> String {
        String(
            format: String(localized: "candidate.offCourse", defaultValue: "%d° off course"),
            Int(degrees.rounded())
        )
    }
}
