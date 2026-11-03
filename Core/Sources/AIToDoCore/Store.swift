import Foundation

public struct RecallHit: Equatable { public var todo: Todo; public var score: Double }

public enum AddResult: Equatable {
    case empty
    case duplicate(Todo)
    /// `inherited` lists what was reused from `prior` ("tags", "priority", "note").
    case added(Todo, inherited: [String], prior: Todo?)
}

/// The memory. Nothing is hard-deleted: finished and deleted todos stay recallable.
public final class TodoStore {
    public private(set) var todos: [UUID: Todo]
    public var onChange: (() -> Void)?
    public var onError: ((Error) -> Void)?
    private let persistence: TodoPersistence
    private let nowProvider: () -> Date
    public let calendar: Calendar

    public init(persistence: TodoPersistence, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) throws {
        self.persistence = persistence
        self.calendar = calendar
        self.nowProvider = now
        self.todos = Dictionary((try persistence.load()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public var now: Date { nowProvider() }
    public var all: [Todo] { Array(todos.values) }
    public var open: [Todo] { all.filter(\.isOpen) }
    public func get(_ id: UUID) -> Todo? { todos[id] }

    private func commit() {
        do { try persistence.save(all) } catch { onError?(error) }
        onChange?()
    }

    // MARK: Writing

    @discardableResult
    public func add(_ text: String) -> AddResult {
        let now = self.now
        let p = TodoParser.parse(text, now: now, calendar: calendar)
        let toks = Text.tokens(p.title)
        guard !p.title.trimmingCharacters(in: .whitespaces).isEmpty else { return .empty }
        if !toks.isEmpty, let dup = open.first(where: { Text.jaccard(Text.tokens($0.title), toks) >= 0.85 }) { return .duplicate(dup) }

        var t = Todo(title: p.title, created: now, due: p.due, allDay: p.allDay, repeatRule: p.repeatRule, priority: p.priority, tags: p.tags)
        var inherited: [String] = []
        let prior = findPrior(p.title)
        if let prior {
            if t.tags.isEmpty && !prior.tags.isEmpty { t.tags = prior.tags; inherited.append("tags") }
            if t.priority == 0 && prior.priority > 0 { t.priority = prior.priority; inherited.append("priority") }
            if !prior.note.isEmpty { t.note = prior.note; inherited.append("note") }
        }
        todos[t.id] = t
        commit()
        return .added(t, inherited: inherited, prior: prior)
    }

    /// "Add again" for a finished todo; restores a deleted one.
    @discardableResult
    public func readd(_ id: UUID) -> Todo? {
        guard let src = todos[id] else { return nil }
        if src.isOpen { return src }
        if src.deleted != nil { return restore(id) }
        let now = self.now
        var t = src
        t.id = UUID(); t.created = now; t.updated = now; t.due = nil; t.allDay = true
        t.done = nil; t.deleted = nil; t.completions = []; t.notified = nil
        if src.repeatRule != nil {
            var probe = src; probe.due = nil; probe.allDay = true
            t.due = Dates.nextDue(of: probe, now: now, calendar: calendar)
        }
        todos[t.id] = t
        commit()
        return t
    }

    @discardableResult
    public func update(_ id: UUID, touch: Bool = true, _ change: (inout Todo) -> Void) -> Todo? {
        guard var t = todos[id] else { return nil }
        change(&t)
        if touch { t.updated = now }
        todos[id] = t
        commit()
        return t
    }

    public struct Completion { public var todo: Todo; public var before: Todo; public var rolled: Bool }

    @discardableResult
    public func complete(_ id: UUID) -> Completion? {
        guard let before = todos[id], before.isOpen else { return nil }
        var t = before
        let now = self.now
        t.completions.append(now)
        t.updated = now
        t.notified = nil
        let next = Dates.nextDue(of: t, now: now, calendar: calendar)
        if t.repeatRule != nil, let next { t.due = next } else { t.done = now }
        todos[id] = t
        commit()
        return Completion(todo: t, before: before, rolled: t.repeatRule != nil && next != nil)
    }

    @discardableResult
    public func uncomplete(_ id: UUID) -> Todo? {
        update(id) { t in t.done = nil; if !t.completions.isEmpty { t.completions.removeLast() } }
    }

    /// Put a todo back exactly as it was (undo).
    public func replace(_ snapshot: Todo) { todos[snapshot.id] = snapshot; commit() }
    @discardableResult public func remove(_ id: UUID) -> Todo? { let n = now; return update(id) { $0.deleted = n } }
    @discardableResult public func restore(_ id: UUID) -> Todo? { update(id) { $0.deleted = nil; $0.done = nil } }

    // MARK: Recall

    /// The most recent earlier todo (any state) that is essentially the same task.
    public func findPrior(_ title: String, minSimilarity: Double = 0.6) -> Todo? {
        let toks = Text.tokens(title)
        guard !toks.isEmpty else { return nil }
        var best: (Todo, Double)?
        for t in all {
            let s = Text.jaccard(Text.tokens(t.title), toks)
            guard s >= minSimilarity else { continue }
            if best == nil || s > best!.1 || (s == best!.1 && t.updated > best!.0.updated) { best = (t, s) }
        }
        return best?.0
    }

    /// Anything ever written that relates to `query`, including done and deleted items.
    /// The last word counts as a prefix while the user is still typing it.
    public func recall(_ query: String, limit: Int = 5, excluding: UUID? = nil) -> [RecallHit] {
        let qt = Text.tokens(query)
        guard !qt.isEmpty else { return [] }
        let typing = !(query.last?.isWhitespace ?? false)
        struct Doc { var todo: Todo; var title: Set<String>; var rest: Set<String> }
        let docs = all.filter { $0.id != excluding }.map {
            Doc(todo: $0, title: Set(Text.tokens($0.title)), rest: Set(Text.tokens($0.note) + $0.tags.flatMap(Text.tokens)))
        }
        var df: [String: Int] = [:]
        for d in docs { for w in d.title.union(d.rest) { df[w, default: 0] += 1 } }
        func idf(_ w: String) -> Double { log(1 + Double(docs.count) / Double(1 + (df[w] ?? 0))) }
        let total = qt.reduce(0) { $0 + idf($1) }
        guard total > 0 else { return [] }

        var hits: [RecallHit] = []
        for d in docs {
            var score = 0.0
            for (i, w) in qt.enumerated() {
                let prefix = typing && i == qt.count - 1 && w.count >= 2
                func hit(_ set: Set<String>, _ weight: Double) -> Double {
                    if set.contains(w) { return weight }
                    if prefix, set.contains(where: { $0.hasPrefix(w) }) { return weight * 0.7 }
                    return 0
                }
                score += idf(w) * max(hit(d.title, 1), hit(d.rest, 0.6))
            }
            score /= total
            if score >= 0.5 { hits.append(RecallHit(todo: d.todo, score: score)) }
        }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.todo.updated > $1.todo.updated }
        return Array(hits.prefix(limit))
    }

    // MARK: Import / export

    public func exportData() throws -> Data { try JSONFilePersistence.exportData(all) }

    /// Merges by recency; returns how many todos were added or updated.
    @discardableResult
    public func importData(_ data: Data) throws -> Int {
        var n = 0
        for t in try JSONFilePersistence.importData(data) {
            if let existing = todos[t.id], existing.updated >= t.updated { continue }
            todos[t.id] = t; n += 1
        }
        commit()
        return n
    }
}
