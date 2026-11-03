import Foundation

public enum InsightAction: String, Equatable {
    case rescheduleToday, scheduleToday, drop, addHabit
    public var label: String {
        switch self {
        case .rescheduleToday: return "Move to today"
        case .scheduleToday: return "Do today"
        case .drop: return "Drop it"
        case .addHabit: return "Add it"
        }
    }
}

public struct Insight: Identifiable, Equatable {
    public enum Kind: String { case overdue, today, stale, habit }
    public var id: String
    public var kind: Kind
    public var text: String
    public var todoIDs: [UUID]
    public var actions: [InsightAction]
    /// For habits: the title to re-add.
    public var title: String?
}

public struct Habit: Equatable { public var title: String; public var typicalDays: Int; public var daysSince: Int; public var count: Int }

/// Proactive nudges computed locally from memory; no AI needed.
public enum Proactive {
    public static func habits(_ todos: [Todo], now: Date, calendar cal: Calendar = .current) -> [Habit] {
        struct Group { var key: String; var title: String; var latest: Date; var times: [Date] = []; var open = false }
        var groups: [String: Group] = [:]
        for t in todos {
            let k = Text.titleKey(t.title)
            guard !k.isEmpty else { continue }
            var g = groups[k] ?? Group(key: k, title: t.title, latest: .distantPast)
            g.times += t.completionDates
            if t.isOpen { g.open = true }
            if t.updated > g.latest { g.latest = t.updated; g.title = t.title }
            groups[k] = g
        }
        var out: [Habit] = []
        for g in groups.values where !g.open {
            // One completion per calendar day, so double taps can't fake a rhythm.
            let days = Set(g.times.map { cal.startOfDay(for: $0) }).sorted()
            guard days.count >= 3 else { continue }
            let gaps = zip(days, days.dropFirst()).map { cal.dateComponents([.day], from: $0, to: $1).day ?? 0 }.filter { $0 >= 1 }
            guard gaps.count >= 2 else { continue }
            let s = gaps.sorted()
            let median = s.count % 2 == 1 ? Double(s[s.count / 2]) : Double(s[s.count / 2 - 1] + s[s.count / 2]) / 2
            let typical = max(1, Int(median.rounded()))
            let since = cal.dateComponents([.day], from: days.last!, to: cal.startOfDay(for: now)).day ?? 0
            if Double(since) >= Double(typical) * 0.85 && since <= typical * 3 {
                out.append(Habit(title: g.title, typicalDays: typical, daysSince: since, count: days.count))
            }
        }
        return out.sorted { Double($0.daysSince) / Double($0.typicalDays) > Double($1.daysSince) / Double($1.typicalDays) }
    }

    public static func insights(_ todos: [Todo], now: Date, calendar cal: Calendar = .current) -> [Insight] {
        let open = todos.filter(\.isOpen)
        var out: [Insight] = []

        let overdue = open.filter { Dates.isOverdue($0, now: now, calendar: cal) }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        if let first = overdue.first {
            out.append(Insight(id: "overdue", kind: .overdue,
                               text: overdue.count == 1 ? "Overdue: \(first.title)" : "\(overdue.count) overdue — oldest is “\(first.title)”",
                               todoIDs: overdue.map(\.id), actions: [.rescheduleToday]))
        }
        let today = open.filter { Dates.isToday($0, now: now, calendar: cal) }
        if let first = today.first {
            out.append(Insight(id: "today", kind: .today, text: today.count == 1 ? "Due today: \(first.title)" : "\(today.count) things due today",
                               todoIDs: today.map(\.id), actions: []))
        }
        let cutoff = now.addingTimeInterval(-14 * 86400)
        if let stale = open.filter({ $0.due == nil && $0.updated < cutoff }).min(by: { $0.updated < $1.updated }) {
            let age = cal.dateComponents([.day], from: stale.updated, to: now).day ?? 14
            out.append(Insight(id: "stale:\(stale.id)", kind: .stale, text: "“\(stale.title)” has sat untouched for \(age) days. Still want it?",
                               todoIDs: [stale.id], actions: [.scheduleToday, .drop]))
        }
        for h in habits(todos, now: now, calendar: cal).prefix(2) {
            let every = h.typicalDays == 1 ? "every day" : h.typicalDays == 7 ? "every week" : "every ~\(h.typicalDays) days"
            let ago = h.daysSince == 0 ? "today" : "\(h.daysSince) \(h.daysSince == 1 ? "day" : "days") ago"
            out.append(Insight(id: "habit:\(Text.titleKey(h.title))", kind: .habit,
                               text: "You usually do “\(h.title)” \(every) — last time was \(ago).", todoIDs: [], actions: [.addHabit], title: h.title))
        }
        return out
    }
}
