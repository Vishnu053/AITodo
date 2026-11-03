import Foundation

public struct ParsedTodo: Equatable {
    public var title = ""
    public var due: Date?
    public var allDay = true
    public var repeatRule: RepeatRule?
    public var priority = 0
    public var tags: [String] = []
}

/// Natural-language capture: "call mum tomorrow 5pm #family !" → structured todo.
/// English only; all dates are interpreted in `calendar`'s time zone.
public enum TodoParser {
    private static let dayRE = "(sunday|sun|monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat)"
    private static let fullDayRE = "(sunday|monday|tuesday|wednesday|thursday|friday|saturday)"
    private static let monthRE = "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
    private static let days = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// A string being consumed phrase by phrase.
    private struct Work {
        var s: String
        /// Removes the first match of `pattern` and returns its capture groups (index 0 = whole match).
        mutating func take(_ pattern: String) -> [String?]? {
            let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let ns = s as NSString
            guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let groups: [String?] = (0..<m.numberOfRanges).map {
                let r = m.range(at: $0)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            s = ns.replacingCharacters(in: m.range, with: " ")
            return groups
        }
        mutating func replaceAll(_ pattern: String, _ body: ([String?]) -> String) {
            let re = try! NSRegularExpression(pattern: pattern)
            let ns = s as NSString
            var out = s as NSString
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
                let groups: [String?] = (0..<m.numberOfRanges).map {
                    let r = m.range(at: $0)
                    return r.location == NSNotFound ? nil : ns.substring(with: r)
                }
                out = out.replacingCharacters(in: m.range, with: body(groups)) as NSString
            }
            s = out as String
        }
    }

    public static func parse(_ input: String, now: Date = Date(), calendar cal: Calendar = .current) -> ParsedTodo {
        let collapsed = input.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        var w = Work(s: " " + collapsed + " ")
        var out = ParsedTodo()
        let today = cal.startOfDay(for: now)

        w.replaceAll(#"(\s)#([\p{L}\p{N}][\p{L}\p{N}_-]*)"#) { g in
            let tag = g[2]!.lowercased()
            if !out.tags.contains(tag) { out.tags.append(tag) }
            return g[1]!
        }
        w.replaceAll(#"(\s)(!{1,3})(?=\s)"#) { g in out.priority = min(2, g[2]!.count); return g[1]! }

        // Repetition
        var weekdayAnchor: Int?
        if let g = w.take(#"\bevery\s+(\d+)\s+(day|week|month|year)s?\b"#) {
            let n = Int(g[1]!)!
            switch g[2]!.lowercased() {
            case "year": out.repeatRule = RepeatRule(unit: .month, interval: 12 * n)
            case "week": out.repeatRule = RepeatRule(unit: .week, interval: n)
            case "month": out.repeatRule = RepeatRule(unit: .month, interval: n)
            default: out.repeatRule = RepeatRule(unit: .day, interval: n)
            }
        } else if w.take(#"\bevery\s+weekday\b"#) != nil {
            out.repeatRule = RepeatRule(unit: .week, weekdays: [1, 2, 3, 4, 5])
        } else if let g = w.take(#"\bevery\s+"# + dayRE + #"\b"#) {
            let dow = days.firstIndex(of: String(g[1]!.lowercased().prefix(3)))!
            out.repeatRule = RepeatRule(unit: .week, weekdays: [dow])
            weekdayAnchor = dow
        } else if let g = w.take(#"\b(?:every\s+(day|week|month|year)|(daily|weekly|monthly|yearly))\b"#) {
            let word = (g[1] ?? g[2]!).lowercased()
            let unit: RepeatRule.Unit = word.hasPrefix("day") || word == "daily" ? .day : word.hasPrefix("week") ? .week : .month
            out.repeatRule = RepeatRule(unit: unit, interval: word.hasPrefix("year") ? 12 : 1)
        }

        var date: Date?
        var minutes: (h: Int, m: Int)?
        var relative: Date?

        // "in 2 hours", "in 3 days"
        if let g = w.take(#"\bin\s+(\d+)\s*(minutes?|mins?|hours?|hrs?|h|days?|d|weeks?|w)\b"#) {
            let n = Int(g[1]!)!
            let u = g[2]!.lowercased()
            if u.hasPrefix("m") { relative = now.addingTimeInterval(Double(n) * 60) }
            else if u.hasPrefix("h") { relative = now.addingTimeInterval(Double(n) * 3600) }
            else if u.hasPrefix("d") { date = cal.addingDays(n, to: today) }
            else { date = cal.addingDays(7 * n, to: today) }
        }

        // Explicit dates
        if relative == nil && date == nil {
            if let g = w.take(#"\b(\d{4})-(\d{2})-(\d{2})\b"#) {
                date = cal.date(from: DateComponents(year: Int(g[1]!), month: Int(g[2]!), day: Int(g[3]!)))
            } else if let g = w.take(#"\b(?:on\s+)?"# + monthRE + #"\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b"#) {
                date = pick(month: monthIndex(g[1]!), day: Int(g[2]!)!, year: g[3].flatMap { Int($0) }, now: now, cal: cal)
            } else if let g = w.take(#"\b(?:on\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+"# + monthRE + #"\b(?:,?\s+(\d{4}))?"#) {
                date = pick(month: monthIndex(g[2]!), day: Int(g[1]!)!, year: g[3].flatMap { Int($0) }, now: now, cal: cal)
            } else if let g = w.take(#"\b(today|tonight|tomorrow|tmrw|tmr)\b"#) {
                let word = g[1]!.lowercased()
                date = word == "today" || word == "tonight" ? today : cal.addingDays(1, to: today)
                if word == "tonight" { minutes = (20, 0) }
            } else if let g = w.take(#"\b(?:on|next|this|by)\s+"# + dayRE + #"\b"#) ?? w.take(#"\b"# + fullDayRE + #"\b"#) {
                // Bare short names ("sat", "sun", "mon") are too ambiguous without a preposition.
                date = nextWeekday(from: now, dow: dayIndex(g.last!!), inclusive: false, cal: cal)
            }
        }

        // Time of day
        if let g = w.take(#"\b(?:at\s+|@\s*)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)(?=\s|[.,;!?]|$)"#) {
            var h = Int(g[1]!)! % 12
            if g[3]!.lowercased().hasPrefix("p") { h += 12 }
            minutes = (h, Int(g[2] ?? "0")!)
        } else if let g = w.take(#"\b(?:at|@)\s*([01]?\d|2[0-3]):([0-5]\d)\b"#) {
            minutes = (Int(g[1]!)!, Int(g[2]!)!)
        } else if let g = w.take(#"\bat\s+(1[0-2]|[1-9])\b(?!\s*(?:st|nd|rd|th|people|things|items))"#) {
            let h = Int(g[1]!)!
            minutes = (h >= 1 && h <= 6 ? h + 12 : h, 0) // "at 5" is 5pm, "at 9" is 9am
        } else if w.take(#"\b(noon|midday)\b"#) != nil {
            minutes = (12, 0)
        } else if w.take(#"\bmidnight\b"#) != nil {
            minutes = (23, 59)
        }

        // Compose
        if let relative {
            out.due = relative
            out.allDay = false
        } else {
            if date == nil, let r = out.repeatRule {
                if let anchor = weekdayAnchor { date = nextWeekday(from: now, dow: anchor, inclusive: true, cal: cal) }
                else if let wd = r.weekdays { date = firstWeekday(onOrAfter: today, in: wd, cal: cal) }
                else { date = today }
            }
            if date == nil, let m = minutes {
                date = today
                if let t = cal.date(bySettingHour: m.h, minute: m.m, second: 0, of: today), t <= now { date = cal.addingDays(1, to: today) }
            }
            if let d = date {
                if let m = minutes {
                    out.due = cal.date(bySettingHour: m.h, minute: m.m, second: 0, of: d)
                    out.allDay = false
                } else {
                    out.due = d
                }
            }
        }

        var title = w.s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        title = title.replacingOccurrences(of: #"^(?:by|due|on|at)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"\s+(?:on|at|by|due|in|from|until|before|for|every|next|this)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"[\s,;:-]+$"#, with: "", options: .regularExpression)
        if title.isEmpty { title = collapsed }
        out.title = title.prefix(1).uppercased() + title.dropFirst()
        return out
    }

    private static func dayIndex(_ s: String) -> Int { days.firstIndex(of: String(s.lowercased().prefix(3)))! }
    private static func monthIndex(_ s: String) -> Int { months.firstIndex(of: String(s.lowercased().prefix(3)))! + 1 }

    private static func pick(month: Int, day: Int, year: Int?, now: Date, cal: Calendar) -> Date? {
        if let year { return cal.date(from: DateComponents(year: year, month: month, day: day)) }
        let y = cal.component(.year, from: now)
        guard var d = cal.date(from: DateComponents(year: y, month: month, day: day)) else { return nil }
        // A date a few days back is most likely an overdue item, not next year's.
        if d < cal.addingDays(-30, to: cal.startOfDay(for: now)) { d = cal.date(from: DateComponents(year: y + 1, month: month, day: day)) ?? d }
        return d
    }

    private static func nextWeekday(from d: Date, dow: Int, inclusive: Bool, cal: Calendar) -> Date {
        var diff = (dow - cal.weekdayIndex(d) + 7) % 7
        if diff == 0 && !inclusive { diff = 7 }
        return cal.addingDays(diff, to: cal.startOfDay(for: d))
    }

    private static func firstWeekday(onOrAfter d: Date, in wd: [Int], cal: Calendar) -> Date {
        var x = d
        for _ in 0..<7 where !wd.contains(cal.weekdayIndex(x)) { x = cal.addingDays(1, to: x) }
        return x
    }
}
