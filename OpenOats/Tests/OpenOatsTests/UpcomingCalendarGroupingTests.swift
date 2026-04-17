import XCTest
@testable import OpenOatsKit

final class UpcomingCalendarGroupingTests: XCTestCase {
    func testSectionTitleUsesTodayAndTomorrowLabels() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let todayGroup = UpcomingCalendarGrouping.DayGroup(
            date: today,
            events: [makeEvent(id: "today", title: "Demo Day", start: today)]
        )
        let tomorrowGroup = UpcomingCalendarGrouping.DayGroup(
            date: tomorrow,
            events: [makeEvent(id: "tomorrow", title: "Planning", start: tomorrow)]
        )

        XCTAssertEqual(todayGroup.sectionTitle, "Today")
        XCTAssertEqual(tomorrowGroup.sectionTitle, "Tomorrow")
    }

    func testGroupsEventsByDayAndSortsWithinEachDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let morning = makeDate(year: 2026, month: 4, day: 20, hour: 9, minute: 45, calendar: calendar)
        let midday = makeDate(year: 2026, month: 4, day: 20, hour: 11, minute: 30, calendar: calendar)
        let nextDay = makeDate(year: 2026, month: 4, day: 21, hour: 14, minute: 30, calendar: calendar)

        let events = [
            makeEvent(id: "later", title: "Product Planning", start: midday),
            makeEvent(id: "next", title: "Platform Feedback", start: nextDay),
            makeEvent(id: "first", title: "Payment Ops", start: morning),
        ]

        let groups = UpcomingCalendarGrouping.groups(for: events, calendar: calendar)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].events.map(\.id), ["first", "later"])
        XCTAssertEqual(groups[1].events.map(\.id), ["next"])
    }

    func testGroupDateUsesStartOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let eventDate = makeDate(year: 2026, month: 4, day: 22, hour: 9, minute: 45, calendar: calendar)
        let groups = UpcomingCalendarGrouping.groups(
            for: [makeEvent(id: "event", title: "Payment Ops", start: eventDate)],
            calendar: calendar
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].date, calendar.startOfDay(for: eventDate))
    }

    private func makeEvent(id: String, title: String, start: Date) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            organizer: nil,
            participants: [],
            isOnlineMeeting: false,
            meetingURL: nil
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
