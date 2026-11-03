import Foundation

public protocol TodoPersistence {
    func load() throws -> [Todo]
    func save(_ todos: [Todo]) throws
}

public final class InMemoryPersistence: TodoPersistence {
    public var todos: [Todo]
    public init(_ todos: [Todo] = []) { self.todos = todos }
    public func load() throws -> [Todo] { todos }
    public func save(_ todos: [Todo]) throws { self.todos = todos }
}

/// One JSON file, written atomically, so a crash can never leave a half-written memory.
public final class JSONFilePersistence: TodoPersistence {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static func makeDecoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d }
    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }

    struct File: Codable { var app = "aitodo-ios"; var version = 1; var todos: [Todo] }

    public func load() throws -> [Todo] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Self.makeDecoder().decode(File.self, from: Data(contentsOf: url)).todos
    }

    public func save(_ todos: [Todo]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.exportData(todos).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public static func exportData(_ todos: [Todo]) throws -> Data { try makeEncoder().encode(File(todos: todos)) }

    /// Reads either this app's export or the earlier web version's export.
    public static func importData(_ data: Data) throws -> [Todo] {
        if let f = try? makeDecoder().decode(File.self, from: data) { return f.todos }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let map = root["todos"] as? [String: [String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        func date(_ v: Any?) -> Date? {
            if let n = v as? Double { return Date(timeIntervalSince1970: n / 1000) }
            if let s = v as? String { return iso.date(from: s) ?? iso2.date(from: s) }
            return nil
        }
        return map.values.compactMap { o in
            guard let title = o["title"] as? String, !title.isEmpty else { return nil }
            let created = date(o["created"]) ?? Date()
            var t = Todo(id: (o["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(), title: title, note: o["note"] as? String ?? "",
                         created: created, due: date(o["due"]), allDay: o["allDay"] as? Bool ?? true,
                         priority: min(2, max(0, o["priority"] as? Int ?? 0)), tags: o["tags"] as? [String] ?? [])
            t.updated = date(o["updated"]) ?? created
            t.done = date(o["done"]); t.deleted = date(o["deleted"])
            t.completions = (o["completions"] as? [Any] ?? []).compactMap(date)
            if let r = o["repeat"] as? [String: Any], let u = (r["unit"] as? String).flatMap(RepeatRule.Unit.init(rawValue:)) {
                t.repeatRule = RepeatRule(unit: u, interval: r["interval"] as? Int ?? 1, weekdays: r["weekdays"] as? [Int])
            }
            return t
        }
    }
}
