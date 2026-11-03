import Foundation

public struct RepeatRule: Codable, Equatable, Hashable {
    public enum Unit: String, Codable { case day, week, month }
    public var unit: Unit
    public var interval: Int
    /// 0 = Sunday … 6 = Saturday (same convention as Calendar.weekday - 1).
    public var weekdays: [Int]?

    public init(unit: Unit, interval: Int = 1, weekdays: [Int]? = nil) {
        self.unit = unit
        self.interval = max(1, interval)
        self.weekdays = weekdays
    }
}

/// The few repeat rules the editor and the on-device model can pick from.
public enum RepeatPreset: String, CaseIterable, Identifiable {
    case daily, weekdays, weekly, monthly
    public var id: String { rawValue }
    public var rule: RepeatRule {
        switch self {
        case .daily: return RepeatRule(unit: .day)
        case .weekdays: return RepeatRule(unit: .week, weekdays: [1, 2, 3, 4, 5])
        case .weekly: return RepeatRule(unit: .week)
        case .monthly: return RepeatRule(unit: .month)
        }
    }
    public var label: String { rawValue.capitalized }
    public static func matching(_ rule: RepeatRule?) -> RepeatPreset? {
        guard let rule else { return nil }
        return allCases.first { $0.rule == rule }
    }
}

public struct Todo: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var note: String
    public var created: Date
    public var updated: Date
    public var due: Date?
    public var allDay: Bool
    public var repeatRule: RepeatRule?
    /// 0 normal, 1 high, 2 urgent.
    public var priority: Int
    public var tags: [String]
    public var done: Date?
    /// Deleted todos are kept so they can still be recalled and restored.
    public var deleted: Date?
    public var completions: [Date]
    public var notified: Date?

    public init(id: UUID = UUID(), title: String, note: String = "", created: Date, due: Date? = nil, allDay: Bool = true,
                repeatRule: RepeatRule? = nil, priority: Int = 0, tags: [String] = []) {
        self.id = id; self.title = title; self.note = note; self.created = created; self.updated = created
        self.due = due; self.allDay = allDay; self.repeatRule = repeatRule; self.priority = priority; self.tags = tags
        self.done = nil; self.deleted = nil; self.completions = []; self.notified = nil
    }

    public var isOpen: Bool { done == nil && deleted == nil }
    public enum Status: String { case open, done, deleted }
    public var status: Status { deleted != nil ? .deleted : done != nil ? .done : .open }
    /// Every time this was completed (a one-off keeps its single `done` date).
    public var completionDates: [Date] { !completions.isEmpty ? completions : (done.map { [$0] } ?? []) }
}
