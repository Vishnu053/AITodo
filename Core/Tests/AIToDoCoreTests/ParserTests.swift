import XCTest
@testable import AIToDoCore

final class ParserTests: XCTestCase {
    func testPlainTextStaysATitle() {
        let p = parse("buy oat milk")
        XCTAssertEqual(p.title, "Buy oat milk"); XCTAssertNil(p.due)
    }

    func testTomorrowTimeTagPriority() {
        let p = parse("call mum tomorrow at 5pm #family !!")
        XCTAssertEqual(p.title, "Call mum")
        XCTAssertEqual(parts(p.due), [2026, 11, 4, 17, 0])
        XCTAssertFalse(p.allDay)
        XCTAssertEqual(p.tags, ["family"])
        XCTAssertEqual(p.priority, 2)
    }

    func testWeekdayMeansNextOne() {
        XCTAssertEqual(ymd(parse("review on friday").due), [2026, 11, 6])
        XCTAssertEqual(ymd(parse("standup tuesday").due), [2026, 11, 10])
    }

    func testAmbiguousShortWordsAreNotDates() {
        XCTAssertNil(parse("watch the sun set").due)
        XCTAssertEqual(parse("mon").title, "Mon")
        XCTAssertEqual(ymd(parse("lunch with sam on sat").due), [2026, 11, 7])
    }

    func testRelativeTimes() {
        XCTAssertEqual(parse("stretch in 2 hours").due, NOW.addingTimeInterval(7200))
        XCTAssertEqual(ymd(parse("renew passport in 3 days").due), [2026, 11, 6])
    }

    func testTimeOnlyRollsToTomorrowWhenPassed() {
        XCTAssertEqual(parts(parse("gym 7am").due), [2026, 11, 4, 7, 0])
        XCTAssertEqual(parts(parse("lunch at 12:30").due), [2026, 11, 3, 12, 30])
        XCTAssertEqual(parts(parse("call at 5").due), [2026, 11, 3, 17, 0])
    }

    func testExplicitDatesAndYearRollover() {
        XCTAssertEqual(ymd(parse("dentist nov 20").due), [2026, 11, 20])
        XCTAssertEqual(ymd(parse("taxes 5 jan").due), [2027, 1, 5])
        XCTAssertEqual(ymd(parse("send invoice nov 1").due), [2026, 11, 1]) // recent past stays overdue
        XCTAssertEqual(ymd(parse("flight 2027-03-09").due), [2027, 3, 9])
    }

    func testRepetition() {
        XCTAssertEqual(parse("water plants every 3 days").repeatRule, RepeatRule(unit: .day, interval: 3))
        let w = parse("team sync every monday 9am")
        XCTAssertEqual(w.repeatRule, RepeatRule(unit: .week, weekdays: [1]))
        XCTAssertEqual(parts(w.due), [2026, 11, 9, 9, 0])
        XCTAssertEqual(w.title, "Team sync")
        XCTAssertEqual(parse("floss daily").repeatRule?.unit, .day)
        XCTAssertEqual(Dates.describeRepeat(parse("x every weekday").repeatRule), "Every weekday")
    }

    func testTitleFallbackWhenNothingLeft() { XCTAssertEqual(parse("tomorrow").title, "Tomorrow") }

    func testNextDue() {
        let daily = Todo(title: "x", created: NOW, due: at(2026, 11, 3), allDay: true, repeatRule: RepeatRule(unit: .day))
        XCTAssertEqual(ymd(Dates.nextDue(of: daily, now: NOW, calendar: cal)), [2026, 11, 4])
        let late = Todo(title: "x", created: NOW, due: at(2026, 10, 1), allDay: true, repeatRule: RepeatRule(unit: .week, weekdays: [1]))
        XCTAssertEqual(ymd(Dates.nextDue(of: late, now: NOW, calendar: cal)), [2026, 11, 9])
        let monthly = Todo(title: "x", created: NOW, due: at(2026, 1, 31), allDay: true, repeatRule: RepeatRule(unit: .month))
        XCTAssertEqual(ymd(Dates.nextDue(of: monthly, now: NOW, calendar: cal)).prefix(2), [2026, 11])
    }

    func testFormattingAndOverdue() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(Dates.formatDue(at(2026, 11, 3), allDay: true, now: NOW, calendar: cal, locale: en), "Today")
        // ICU may use a narrow no-break space before "PM".
        XCTAssertEqual(Dates.formatDue(at(2026, 11, 4, 17), allDay: false, now: NOW, calendar: cal, locale: en).replacingOccurrences(of: "\u{202F}", with: " "), "Tomorrow, 5:00 PM")
        XCTAssertEqual(Dates.formatDue(at(2026, 11, 20), allDay: true, now: NOW, calendar: cal, locale: en), "Nov 20")
        func t(_ d: Date, _ allDay: Bool) -> Todo { Todo(title: "x", created: NOW, due: d, allDay: allDay) }
        XCTAssertFalse(Dates.isOverdue(t(at(2026, 11, 3), true), now: NOW, calendar: cal))
        XCTAssertTrue(Dates.isOverdue(t(at(2026, 11, 2), true), now: NOW, calendar: cal))
        XCTAssertTrue(Dates.isOverdue(t(at(2026, 11, 3, 9), false), now: NOW, calendar: cal))
    }

    func testParseLocal() {
        XCTAssertNil(Dates.parseLocal("nope", calendar: cal))
        XCTAssertNil(Dates.parseLocal("2026-02-31", calendar: cal))
        XCTAssertEqual(Dates.parseLocal("2026-11-05", calendar: cal)?.allDay, true)
        XCTAssertEqual(Dates.parseLocal("2026-11-05T14:30", calendar: cal)?.allDay, false)
    }
}
