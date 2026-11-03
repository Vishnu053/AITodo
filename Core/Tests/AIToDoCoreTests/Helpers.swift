import Foundation
@testable import AIToDoCore

/// A fixed, non-UTC calendar so time-zone bugs show up in tests.
let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    c.locale = Locale(identifier: "en_US")
    return c
}()

func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// Tuesday 3 Nov 2026, 10:00 local.
let NOW = at(2026, 11, 3, 10)

func parts(_ d: Date?) -> [Int] {
    guard let d else { return [] }
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
    return [c.year!, c.month!, c.day!, c.hour!, c.minute!]
}
func ymd(_ d: Date?) -> [Int] { Array(parts(d).prefix(3)) }
func parse(_ s: String) -> ParsedTodo { TodoParser.parse(s, now: NOW, calendar: cal) }

final class Clock { var t: Date; init(_ t: Date) { self.t = t } }
func makeStore(_ start: Date = NOW, persistence: TodoPersistence = InMemoryPersistence()) -> (TodoStore, Clock) {
    let clock = Clock(start)
    return (try! TodoStore(persistence: persistence, calendar: cal, now: { clock.t }), clock)
}
func added(_ r: AddResult) -> Todo {
    guard case .added(let t, _, _) = r else { fatalError("expected .added, got \(r)") }
    return t
}
