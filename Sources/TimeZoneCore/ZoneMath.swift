import Foundation

/// All wall-clock <-> instant conversions. Everything goes through `Calendar` so DST and
/// fractional offsets (UTC+5:30, +5:45, +12:45 ...) are handled by the system tz database.
public enum ZoneMath {
    public static let minutesPerDay = 24 * 60

    public static func calendar(for zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    /// Wall-clock minutes since local midnight (0..<1440) of `date` in `zone`.
    public static func minuteOfDay(_ date: Date, in zone: TimeZone) -> Int {
        let c = calendar(for: zone).dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }

    /// Number of calendar days between the local date of `date` and the local date of `anchor`,
    /// both read in `zone` (e.g. +1 when `date` is "tomorrow" relative to `anchor`).
    public static func calendarDays(from anchor: Date, to date: Date, in zone: TimeZone) -> Int {
        let cal = calendar(for: zone)
        return daysBetween(cal.dateComponents([.year, .month, .day], from: anchor),
                           cal.dateComponents([.year, .month, .day], from: date))
    }

    /// Wall-clock minutes of `date` in `zone`, counted from midnight of the day containing `anchor`.
    /// 1440 means "midnight at the start of the next day", -15 means "23:45 the day before".
    public static func minuteOfDay(_ date: Date, relativeToDayOf anchor: Date, in zone: TimeZone) -> Int {
        calendarDays(from: anchor, to: date, in: zone) * minutesPerDay + minuteOfDay(date, in: zone)
    }

    /// The instant at which the wall clock in `zone` reads `minute` minutes after midnight of the
    /// day containing `day` (values outside 0..<1440 roll into neighbouring days).
    ///
    /// DST behaviour (documented in README):
    /// - A wall time that does not exist (spring-forward gap, e.g. 02:30 in New York on the March
    ///   transition day) resolves to the first existing time after the gap (03:00).
    /// - A wall time that occurs twice (fall-back overlap, e.g. 01:30 in New York in November)
    ///   resolves to the first occurrence (the daylight-time one).
    public static func instant(minuteOfDay minute: Int, onDayOf day: Date, in zone: TimeZone) -> Date {
        let cal = calendar(for: zone)
        let dayShift = Int((Double(minute) / Double(minutesPerDay)).rounded(.down))
        let wall = minute - dayShift * minutesPerDay
        // Noon always exists, so it is a safe handle on "that calendar day".
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let targetNoon = cal.date(byAdding: .day, value: dayShift, to: noon)!
        return cal.date(bySettingHour: wall / 60, minute: wall % 60, second: 0, of: targetNoon,
                        matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)!
    }

    /// Calendar-day difference of `date` in `zone` versus the same instant in `reference`
    /// (e.g. Tokyo is +1 when it is already tomorrow there).
    public static func dayDifference(at date: Date, in zone: TimeZone, relativeTo reference: TimeZone) -> Int {
        daysBetween(calendar(for: reference).dateComponents([.year, .month, .day], from: date),
                    calendar(for: zone).dateComponents([.year, .month, .day], from: date))
    }

    /// "+1 day", "−1 day", "+2 days" or nil when on the same day.
    public static func dayDifferenceLabel(_ days: Int) -> String? {
        guard days != 0 else { return nil }
        let sign = days > 0 ? "+" : "\u{2212}"
        return "\(sign)\(abs(days)) day\(abs(days) == 1 ? "" : "s")"
    }

    /// "UTC", "UTC+9", "UTC+5:30", "UTC−3" for the offset in effect at `date`.
    public static func utcOffsetLabel(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        guard seconds != 0 else { return "UTC" }
        let sign = seconds > 0 ? "+" : "\u{2212}"
        let h = abs(seconds) / 3600, m = abs(seconds) % 3600 / 60
        return m == 0 ? "UTC\(sign)\(h)" : String(format: "UTC%@%d:%02d", sign, h, m)
    }

    /// Rounds wall-clock minutes to the nearest `step`.
    public static func snap(_ minute: Double, step: Int = 15) -> Int {
        Int((minute / Double(step)).rounded()) * step
    }

    /// "+3h 15m", "−45m", "+1d 2h" — the distance of `date` from `now`, rounded to whole minutes.
    public static func offsetLabel(from now: Date, to date: Date) -> String {
        let total = Int((date.timeIntervalSince(now) / 60).rounded())
        guard total != 0 else { return "now" }
        let sign = total > 0 ? "+" : "\u{2212}"
        let d = abs(total) / 1440, h = abs(total) % 1440 / 60, m = abs(total) % 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        return sign + parts.joined(separator: " ")
    }

    private static func daysBetween(_ a: DateComponents, _ b: DateComponents) -> Int {
        // Compare the two civil dates on a fixed UTC calendar so only the dates matter.
        let utc = calendar(for: TimeZone(identifier: "UTC")!)
        let da = utc.date(from: DateComponents(year: a.year, month: a.month, day: a.day))!
        let db = utc.date(from: DateComponents(year: b.year, month: b.month, day: b.day))!
        return utc.dateComponents([.day], from: da, to: db).day!
    }
}
