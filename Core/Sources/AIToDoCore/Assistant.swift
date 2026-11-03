import Foundation

/// A suggestion from the on-device model, before validation. The model is treated as
/// untrusted: `sanitized()` clamps everything, and `TodoStore.apply` only ever fills gaps.
public struct AISuggestion: Equatable {
    public var title: String?
    public var note: String?
    /// "YYYY-MM-DD" or "YYYY-MM-DDTHH:mm", local time.
    public var due: String?
    public var repeatPreset: RepeatPreset?
    public var priority: Int?
    public var tags: [String]?

    public init(title: String? = nil, note: String? = nil, due: String? = nil, repeatPreset: RepeatPreset? = nil, priority: Int? = nil, tags: [String]? = nil) {
        self.title = title; self.note = note; self.due = due; self.repeatPreset = repeatPreset; self.priority = priority; self.tags = tags
    }

    public func sanitized(calendar: Calendar = .current) -> AISuggestion {
        func clean(_ s: String?, _ max: Int) -> String? {
            let v = (s ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return v.isEmpty ? nil : String(v.prefix(max))
        }
        var out = AISuggestion()
        out.title = clean(title, 200)
        out.note = clean(note, 1000)
        if let due, Dates.parseLocal(due, calendar: calendar) != nil { out.due = due }
        out.repeatPreset = repeatPreset
        if let priority, (1...2).contains(priority) { out.priority = priority }
        let t = Array(Set((tags ?? []).map { $0.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }.filter { !$0.isEmpty }.map { String($0.prefix(30)) })).sorted().prefix(3)
        if !t.isEmpty { out.tags = Array(t) }
        return out
    }
}

public extension TodoStore {
    /// Merge a suggestion into a todo. Only fills gaps and never overwrites user input;
    /// skipped entirely if the user edited the todo since `stamp`. Returns the new todo if anything changed.
    @discardableResult
    func apply(_ s: AISuggestion, to id: UUID, ifUnchangedSince stamp: Date) -> Todo? {
        guard let cur = get(id), cur.updated == stamp else { return nil }
        let s = s.sanitized(calendar: calendar)
        var changed = false
        let result = update(id) { t in
            if let title = s.title, title != t.title { t.title = title; changed = true }
            if let note = s.note, t.note.isEmpty { t.note = note; changed = true }
            if t.due == nil, let due = s.due, let p = Dates.parseLocal(due, calendar: calendar) { t.due = p.date; t.allDay = p.allDay; changed = true }
            if t.repeatRule == nil, let r = s.repeatPreset { t.repeatRule = r.rule; changed = true }
            if t.priority == 0, let p = s.priority { t.priority = p; changed = true }
            if t.tags.isEmpty, let tags = s.tags { t.tags = tags; changed = true }
        }
        return changed ? result : nil
    }
}

/// Prompt text for the model. Kept here (pure) so it is covered by tests. Todo text is wrapped as data.
public enum AIPrompts {
    public static func stamp(_ now: Date, calendar cal: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = cal; f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm EEEE"
        return f.string(from: now)
    }

    public static func refine(text: String, now: Date, memory: [Todo], calendar cal: Calendar = .current) -> String {
        let mem = memory.prefix(5).map { m -> String in
            var line = "- \"\(m.title.prefix(120))\" [\(m.status.rawValue)"
            let n = m.completionDates.count
            if n > 0 { line += ", done \(n)x" }
            line += "]"
            if !m.tags.isEmpty { line += " tags: " + m.tags.joined(separator: ",") }
            if !m.note.isEmpty { line += " note: \(m.note.prefix(100))" }
            return line
        }.joined(separator: "\n")
        return """
        Now (user local time): \(stamp(now, calendar: cal))
        <todo>\(text.prefix(500))</todo>
        <memory>
        \(mem.isEmpty ? "(none)" : mem)
        </memory>
        """
    }

    /// Numbered so the small on-device model can point at todos by number instead of copying ids.
    public struct BriefInput {
        public let prompt: String
        public let index: [Int: UUID]
        public func resolve(_ numbers: [Int]) -> [UUID] { Array(numbers.compactMap { index[$0] }.prefix(3)) }
    }

    public static func brief(todos: [Todo], now: Date, calendar cal: Calendar = .current) -> BriefInput {
        let open = todos.filter(\.isOpen).sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }.prefix(20)
        var index: [Int: UUID] = [:]
        var lines: [String] = []
        for (i, t) in open.enumerated() {
            index[i + 1] = t.id
            var l = "\(i + 1). \(t.title.prefix(80))"
            if let due = t.due { l += " (due \(Dates.formatDue(due, allDay: t.allDay, now: now, calendar: cal, locale: Locale(identifier: "en_US")))\(Dates.isOverdue(t, now: now, calendar: cal) ? ", OVERDUE" : ""))" }
            if t.priority > 0 { l += " [priority \(t.priority)]" }
            lines.append(l)
        }
        let recent = todos.flatMap { t in t.completionDates.map { (t.title, $0) } }.sorted { $0.1 > $1.1 }.prefix(5)
            .map { "- \($0.0.prefix(60)) (\(cal.dateComponents([.day], from: $0.1, to: now).day ?? 0)d ago)" }.joined(separator: "\n")
        let habits = Proactive.habits(todos, now: now, calendar: cal).prefix(2).map { "- \($0.title.prefix(60)): every ~\($0.typicalDays) days, last \($0.daysSince)d ago" }.joined(separator: "\n")
        let prompt = """
        Now (user local time): \(stamp(now, calendar: cal))
        <data>
        Open todos:
        \(lines.joined(separator: "\n"))
        Recently done:
        \(recent.isEmpty ? "(none)" : recent)
        Habits:
        \(habits.isEmpty ? "(none)" : habits)
        </data>
        """
        return BriefInput(prompt: prompt, index: index)
    }
}
