import Foundation

public extension Calendar {
    func addingDays(_ n: Int, to d: Date) -> Date { date(byAdding: .day, value: n, to: d) ?? d }
    func addingMonths(_ n: Int, to d: Date) -> Date {
        // Calendar clamps (Jan 31 + 1 month = Feb 28/29), matching the web version.
        date(byAdding: .month, value: n, to: d) ?? d
    }
    /// 0 = Sunday … 6 = Saturday.
    func weekdayIndex(_ d: Date) -> Int { component(.weekday, from: d) - 1 }
}

public enum Dates {
    public static func isOverdue(_ t: Todo, now: Date, calendar cal: Calendar = .current) -> Bool {
        guard let due = t.due else { return false }
        return t.allDay ? due < cal.startOfDay(for: now) : due < now
    }

    public static func isToday(_ t: Todo, now: Date, calendar cal: Calendar = .current) -> Bool {
        guard let due = t.due else { return false }
        return cal.isDate(due, inSameDayAs: now) && !isOverdue(t, now: now, calendar: cal)
    }

    /// "2026-11-03" in the calendar's time zone; used for per-day caches and file names.
    public static func dayKey(_ d: Date, calendar cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func describeRepeat(_ r: RepeatRule?) -> String {
        guard let r else { return "" }
        if let days = r.weekdays, !days.isEmpty {
            if days.count == 5 && !days.contains(0) && !days.contains(6) { return "Every weekday" }
            let names = Calendar(identifier: .gregorian).shortWeekdaySymbols
            return "Every " + days.sorted().map { names[$0] }.joined(separator: ", ")
        }
        if r.unit == .month && r.interval % 12 == 0 {
            return r.interval == 12 ? "Yearly" : "Every \(r.interval / 12) years"
        }
        if r.interval == 1 { return ["day": "Daily", "week": "Weekly", "month": "Monthly"][r.unit.rawValue]! }
        return "Every \(r.interval) \(r.unit.rawValue)s"
    }

    public static func formatDue(_ due: Date, allDay: Bool, now: Date, calendar cal: Calendar = .current, locale: Locale = .current) -> String {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        let f = DateFormatter()
        f.locale = locale
        f.calendar = cal
        f.timeZone = cal.timeZone
        let label: String
        switch days {
        case 0: label = "Today"
        case 1: label = "Tomorrow"
        case -1: label = "Yesterday"
        case 2...6: f.setLocalizedDateFormatFromTemplate("EEEE"); label = f.string(from: due)
        default:
            let sameYear = cal.component(.year, from: due) == cal.component(.year, from: now)
            f.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdy")
            label = f.string(from: due)
        }
        guard !allDay else { return label }
        f.dateFormat = nil
        f.dateStyle = .none
        f.timeStyle = .short
        return "\(label), \(f.string(from: due))"
    }

    /// Next due date after completing a repeating todo, strictly in the future.
    public static func nextDue(of t: Todo, now: Date, calendar cal: Calendar = .current) -> Date? {
        guard let r = t.repeatRule else { return nil }
        var d = t.due ?? now
        let limit = t.allDay ? cal.addingDays(1, to: cal.startOfDay(for: now)) : now
        for _ in 0..<2000 {
            d = step(d, r, cal)
            if t.allDay ? d >= limit : d > limit { return d }
        }
        return d
    }

    private static func step(_ d: Date, _ r: RepeatRule, _ cal: Calendar) -> Date {
        if let days = r.weekdays, !days.isEmpty {
            var x = cal.addingDays(1, to: d)
            for _ in 0..<7 where !days.contains(cal.weekdayIndex(x)) { x = cal.addingDays(1, to: x) }
            return x
        }
        switch r.unit {
        case .day: return cal.addingDays(r.interval, to: d)
        case .week: return cal.addingDays(7 * r.interval, to: d)
        case .month: return cal.addingMonths(r.interval, to: d)
        }
    }

    /// "YYYY-MM-DD" or "YYYY-MM-DDTHH:mm" in the user's local time (the format the model is asked for).
    public static func parseLocal(_ s: String, calendar cal: Calendar = .current) -> (date: Date, allDay: Bool)? {
        let r = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?$"#)
        let ns = s as NSString
        guard let m = r.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func g(_ i: Int) -> Int? { m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i))) }
        var c = DateComponents(year: g(1), month: g(2), day: g(3), hour: g(4) ?? 0, minute: g(5) ?? 0)
        c.timeZone = cal.timeZone
        guard let d = cal.date(from: c), cal.component(.day, from: d) == c.day else { return nil }
        return (d, g(4) == nil)
    }
}
