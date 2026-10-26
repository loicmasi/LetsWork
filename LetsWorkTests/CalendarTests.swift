import Foundation
import Testing
@testable import LetsWork

/// Lundi 26 octobre 2026, 14:00 à Paris.
private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()
private let french = Locale(identifier: "fr_FR")
private let now = paris.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 14))!

private func event(
    _ title: String = "Réunion",
    startsIn minutes: Double,
    lasting duration: Double = 30,
    id: String? = nil,
    externalID: String? = nil,
    isAllDay: Bool = false
) -> CalendarEvent {
    let start = now.addingTimeInterval(minutes * 60)
    return CalendarEvent(
        id: id ?? "\(title)|\(minutes)",
        externalID: externalID,
        title: title,
        start: start,
        end: start.addingTimeInterval(duration * 60),
        isAllDay: isAllDay,
        calendarID: "travail",
        calendarTitle: "Travail",
        color: .fallback
    )
}

struct MeetingLinkDetectorTests {
    @Test(arguments: [
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc", MeetingService.teams),
        ("https://meet.google.com/abc-defg-hij", .meet),
        ("https://us02web.zoom.us/j/81234567890?pwd=xyz", .zoom),
        ("https://acme.webex.com/meet/jdoe", .webex),
    ])
    func recognizesMeetingServices(link: String, service: MeetingService) throws {
        let url = try #require(URL(string: link))
        #expect(MeetingLinkDetector.meetingLink(from: url)?.service == service)
    }

    @Test func ignoresOrdinaryLinks() throws {
        #expect(MeetingLinkDetector.meetingLink(from: try #require(URL(string: "https://zoom.us/pricing"))) == nil)
        #expect(MeetingLinkDetector.meetingLink(from: try #require(URL(string: "https://www.apple.com"))) == nil)
    }

    @Test func findsTheLinkInNotes() {
        let notes = "Bonjour,\nRejoindre la réunion : <https://teams.microsoft.com/l/meetup-join/abc>\nMerci"
        let link = MeetingLinkDetector.detect(url: nil, location: "Salle B", notes: notes)
        #expect(link?.service == .teams)
    }

    @Test func prefersTheEventURL() throws {
        let url = try #require(URL(string: "https://meet.google.com/aaa-bbbb-ccc"))
        let link = MeetingLinkDetector.detect(url: url, location: "https://zoom.us/j/1", notes: nil)
        #expect(link?.service == .meet)
    }
}

struct EventTimingTests {
    private func label(_ event: CalendarEvent) -> String {
        EventTiming.shortLabel(for: event, now: now, calendar: paris, locale: french)
    }

    @Test func describesHowSoonTheEventStarts() {
        #expect(label(event(startsIn: -10)) == "en cours")
        #expect(label(event(startsIn: 11.2)) == "dans 12 min")
        #expect(label(event(startsIn: 60)) == "dans 1 h")
        #expect(label(event(startsIn: 65)) == "dans 1 h 05")
        #expect(label(event(startsIn: 4 * 60)) == "à 18:00")
        #expect(label(event(startsIn: 19 * 60)) == "demain à 9:00")
    }

    @Test func formatsTheTimeRange() {
        #expect(EventTiming.range(of: event(startsIn: 0, lasting: 90), calendar: paris, locale: french) == "14:00 – 15:30")
        #expect(EventTiming.range(of: event(startsIn: 0, isAllDay: true)) == "Toute la journée")
    }
}

struct CalendarAggregatorTests {
    @Test func dropsCopiesOfTheSameInvitation() {
        let exchange = event("Point hebdo", startsIn: 30, id: "a", externalID: "uid-1")
        var google = event("Point Hebdo ", startsIn: 30, id: "b", externalID: "uid-1")
        google.calendarID = "perso"
        #expect(CalendarAggregator.merge([[exchange], [google]]).map(\.id) == ["a"])
    }

    @Test func dropsSameTitleAndTimesWithoutSharedIdentifier() {
        let first = event("Revue  produit", startsIn: 30, id: "a", externalID: "uid-1")
        let second = event("revue produit", startsIn: 30, id: "b", externalID: "uid-2")
        #expect(CalendarAggregator.merge([[first, second]]).count == 1)
    }

    @Test func keepsOccurrencesOfARecurringEvent() {
        let monday = event("Daily", startsIn: 30, id: "a", externalID: "uid-1")
        let tuesday = event("Daily", startsIn: 30 + 24 * 60, id: "b", externalID: "uid-1")
        #expect(CalendarAggregator.merge([[tuesday, monday]]).map(\.id) == ["a", "b"])
    }
}

struct CalendarScheduleTests {
    @Test func compactShowsTheOngoingEventFirst() {
        let ongoing = event("En cours", startsIn: -10)
        let soon = event("Bientôt", startsIn: 20)
        #expect(CalendarSchedule.current(in: [soon, ongoing], at: now)?.title == "En cours")
    }

    @Test func compactShowsEventsStartingWithinTheHour() {
        #expect(CalendarSchedule.current(in: [event(startsIn: 45)], at: now) != nil)
        #expect(CalendarSchedule.current(in: [event(startsIn: 90)], at: now) == nil)
    }

    @Test func compactIgnoresAllDayAndEndedEvents() {
        let allDay = event("Congés", startsIn: -60, lasting: 24 * 60, isAllDay: true)
        let ended = event("Fini", startsIn: -60, lasting: 30)
        #expect(CalendarSchedule.current(in: [allDay, ended], at: now) == nil)
    }

    @Test func nextLooksBeyondTheHour() {
        #expect(CalendarSchedule.next(in: [event("Demain", startsIn: 20 * 60)], at: now)?.title == "Demain")
    }

    @Test func alertsOnceWithinTheLeadTime() {
        let meeting = event(startsIn: 4)
        let lead: TimeInterval = 5 * 60
        #expect(CalendarSchedule.dueAlert(in: [meeting], at: now, lead: lead, alreadyAlerted: []) == meeting)
        #expect(CalendarSchedule.dueAlert(in: [meeting], at: now, lead: lead, alreadyAlerted: [meeting.id]) == nil)
        #expect(CalendarSchedule.dueAlert(in: [event(startsIn: 8)], at: now, lead: lead, alreadyAlerted: []) == nil)
        #expect(CalendarSchedule.dueAlert(in: [event(startsIn: -1)], at: now, lead: lead, alreadyAlerted: []) == nil)
    }

    @Test func wakesUpAtTheNextChange() {
        let meeting = event(startsIn: 90)
        let wake = CalendarSchedule.nextBoundary(in: [meeting], after: now, lead: 5 * 60)
        #expect(wake == meeting.start.addingTimeInterval(-CalendarSchedule.lookahead))
    }

    @Test func listsTheDayWithAllDayEventsFirst() {
        let morning = event("Matin", startsIn: -4 * 60)
        let allDay = event("Congés", startsIn: -14 * 60, lasting: 24 * 60, isAllDay: true)
        let tomorrow = event("Demain", startsIn: 20 * 60)
        let day = CalendarSchedule.events(on: now, in: [tomorrow, morning, allDay], calendar: paris)
        #expect(day.map(\.title) == ["Congés", "Matin"])
    }
}

@MainActor
struct CalendarIslandTests {
    let island = IslandModel(metrics: IslandMetrics(notch: NotchGeometry(size: CGSize(width: 185, height: 32), hasNotch: true)))

    private func coordinator() -> ActivityCoordinator {
        ActivityCoordinator(island: island, media: MediaService(), hud: HUDService(), calendar: CalendarService(providers: []))
    }

    @Test func upcomingMeetingShowsTheCalendarCompact() {
        let coordinator = coordinator()
        coordinator.calendarDidChange(event(startsIn: 20))
        #expect(island.activity == .calendar)
        #expect(island.state == .compact)
        #expect(island.metrics.size(for: .compact, activity: .calendar).width == 185 + 2 * IslandMetrics.calendarWingWidth)
    }

    @Test func playbackTakesPrecedenceOverTheMeeting() {
        let coordinator = coordinator()
        coordinator.calendarDidChange(event(startsIn: 20))
        coordinator.mediaDidChange(from: nil, to: NowPlaying(title: "Club", isPlaying: true))
        #expect(island.activity == .media)
    }

    @Test func alertShowsAboveTheCompactAndHoverWins() {
        let coordinator = coordinator()
        coordinator.showAlert(event(startsIn: 5))
        #expect(island.state == .alert)
        island.togglePinned()
        #expect(island.state == .expanded)
        island.dismissPin()
        island.setAlert(nil)
        #expect(island.state == .closed)
    }

    @Test func homeSummarizesTheNextEvent() {
        #expect(HomeView.eventSummary(of: event("Point", startsIn: -5), now: now) == "En cours : Point")
        #expect(HomeView.eventSummary(of: event("Point", startsIn: 12), now: now) == "Prochain : Point · dans 12 min")
    }
}

struct MonthGridTests {
    private var frenchCalendar: Calendar {
        var calendar = paris
        calendar.locale = french
        calendar.firstWeekday = 2
        return calendar
    }

    private func days(_ grid: MonthGrid) -> [[Int?]] {
        grid.weeks.map { week in week.map { $0.map { frenchCalendar.component(.day, from: $0) } } }
    }

    @Test func octoberStartsOnThursdayAndSpansFiveWeeks() {
        let grid = MonthGrid(containing: now, calendar: frenchCalendar)
        #expect(grid.weekdaySymbols == ["L", "M", "M", "J", "V", "S", "D"])
        #expect(days(grid).first == [nil, nil, nil, 1, 2, 3, 4])
        #expect(days(grid).last == [26, 27, 28, 29, 30, 31, nil])
        #expect(grid.weeks.count == 5)
    }

    @Test func monthStartingOnSundayNeedsSixWeeks() throws {
        let march = try #require(frenchCalendar.date(from: DateComponents(year: 2026, month: 3, day: 15)))
        let grid = MonthGrid(containing: march, calendar: frenchCalendar)
        #expect(grid.weeks.count == 6)
        #expect(days(grid).first == [nil, nil, nil, nil, nil, nil, 1])
    }
}

struct EventDraftTests {
    private func at(_ hour: Int, _ minute: Int, second: Int = 0, day: Int = 26) -> Date {
        paris.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    @Test func startsAtTheNextHalfHourToday() {
        #expect(EventDraft(day: now, now: at(14, 10), calendarID: "c", calendar: paris).start == at(14, 30))
        #expect(EventDraft(day: now, now: at(14, 30), calendarID: "c", calendar: paris).start == at(15, 0))
        let draft = EventDraft(day: now, now: at(14, 45, second: 20), calendarID: "c", calendar: paris)
        #expect(draft.start == at(15, 0))
        #expect(draft.end == at(16, 0))
    }

    @Test func startsAtNineAnotherDay() {
        let tomorrow = at(12, 0, day: 27)
        #expect(EventDraft(day: tomorrow, now: at(14, 10), calendarID: "c", calendar: paris).start == at(9, 0, day: 27))
    }

    @Test func movingTheStartKeepsTheDuration() {
        var draft = EventDraft(day: now, now: at(14, 10), calendarID: "c", calendar: paris)
        draft.end = at(16, 0)
        draft.moveStart(to: at(17, 0))
        #expect(draft.end == at(18, 30))
    }

    @Test func explainsWhatIsMissing() {
        var draft = EventDraft(day: now, now: at(14, 10), calendarID: nil, calendar: paris)
        #expect(draft.validationMessage == "Ajoutez un titre.")
        draft.title = "  Point produit  "
        #expect(draft.validationMessage == "Choisissez un calendrier.")
        draft.calendarID = "travail"
        draft.end = draft.start
        #expect(draft.validationMessage == "La fin doit être après le début.")
        draft.end = draft.start.addingTimeInterval(1800)
        draft.urlText = "réunion teams"
        #expect(draft.validationMessage == "Le lien doit commencer par https://.")
        draft.urlText = "https://meet.google.com/abc-defg-hij"
        #expect(draft.validationMessage == nil)
        #expect(draft.trimmedTitle == "Point produit")
        #expect(draft.url?.host == "meet.google.com")
    }

    @Test func allDayEventsCoverWholeDays() {
        var draft = EventDraft(day: now, now: at(14, 10), calendarID: "c", calendar: paris)
        draft.isAllDay = true
        draft.end = at(10, 0, day: 28)
        let dates = draft.normalizedDates(calendar: paris)
        #expect(dates.start == at(0, 0))
        #expect(dates.end == at(0, 0, day: 28))
        #expect(draft.validationMessage == "Ajoutez un titre.")
    }
}
