import CoreGraphics
import Foundation

/// Couleur d'un calendrier en composantes sRGB (la `CGColor` d'EventKit n'est pas `Sendable`).
struct CalendarColor: Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let fallback = CalendarColor(red: 0.45, green: 0.6, blue: 1)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(cgColor: CGColor?) {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let components = cgColor?.converted(to: space, intent: .defaultIntent, options: nil)?.components,
            components.count >= 3
        else {
            self = .fallback
            return
        }
        self.init(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

enum CalendarAccess: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

/// Un calendrier, pour le choix des calendriers affichés.
struct CalendarInfo: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    /// Compte d'origine : « iCloud », « Google », « Exchange »…
    var sourceTitle: String
    var color: CalendarColor
}

enum MeetingService: Equatable, Sendable {
    case teams
    case meet
    case zoom
    case webex

    var name: String {
        switch self {
        case .teams: "Teams"
        case .meet: "Meet"
        case .zoom: "Zoom"
        case .webex: "Webex"
        }
    }
}

struct MeetingLink: Equatable, Sendable {
    var url: URL
    var service: MeetingService
}

struct CalendarEvent: Identifiable, Equatable, Sendable {
    /// Identifiant de l'occurrence : deux occurrences d'un événement répété ont des identifiants distincts.
    var id: String
    /// iCalUID, partagé par les copies d'une même invitation dans plusieurs comptes.
    var externalID: String?
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
    var calendarTitle: String
    var color: CalendarColor
    var location: String?
    var meetingLink: MeetingLink?

    func isOngoing(at date: Date) -> Bool {
        start <= date && date < end
    }

    func hasEnded(at date: Date) -> Bool {
        end <= date
    }
}

/// Repère les liens Teams, Meet, Zoom et Webex dans l'URL, le lieu puis les notes d'un événement.
enum MeetingLinkDetector {
    /// `NSDataDetector` est immuable et sûr entre threads.
    nonisolated(unsafe) private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func detect(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let link = meetingLink(from: url) {
            return link
        }
        for text in [location, notes].compactMap({ $0 }) {
            for url in links(in: text) {
                if let link = meetingLink(from: url) {
                    return link
                }
            }
        }
        return nil
    }

    static func meetingLink(from url: URL) -> MeetingLink? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        let service: MeetingService? =
            if host == "teams.microsoft.com" || host == "teams.live.com" {
                .teams
            } else if host == "meet.google.com" {
                .meet
            } else if host == "zoom.us" || host.hasSuffix(".zoom.us"),
                      ["/j/", "/my/", "/w/"].contains(where: path.hasPrefix) {
                .zoom
            } else if host == "webex.com" || host.hasSuffix(".webex.com") {
                .webex
            } else {
                nil
            }
        return service.map { MeetingLink(url: url, service: $0) }
    }

    private static func links(in text: String) -> [URL] {
        let range = NSRange(text.startIndex..., in: text)
        return linkDetector?.matches(in: text, range: range).compactMap(\.url) ?? []
    }
}

/// Textes de minutage d'un événement.
enum EventTiming {
    /// « en cours », « dans 12 min », « dans 1 h 05 », « à 14:00 », « demain à 9:00 », « mardi à 9:00 ».
    static func shortLabel(for event: CalendarEvent, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if event.isOngoing(at: now) {
            return String(localized: "en cours")
        }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 {
            return String(localized: "maintenant")
        }
        if minutes < 60 {
            return String(localized: "dans \(minutes) min")
        }
        if minutes < 180 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0
                ? String(localized: "dans \(hours) h")
                : String(localized: "dans \(hours) h \(String(format: "%02d", rest))")
        }
        let time = time(of: event.start, calendar: calendar, locale: locale)
        if calendar.isDate(event.start, inSameDayAs: now) {
            return String(localized: "à \(time)")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(event.start, inSameDayAs: tomorrow) {
            return String(localized: "demain à \(time)")
        }
        let weekday = event.start.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
        return String(localized: "\(weekday) à \(time)")
    }

    /// « 14:00 – 15:00 », ou « Toute la journée ».
    static func range(of event: CalendarEvent, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard !event.isAllDay else { return String(localized: "Toute la journée") }
        return "\(time(of: event.start, calendar: calendar, locale: locale)) – \(time(of: event.end, calendar: calendar, locale: locale))"
    }

    static func time(of date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }
}

/// Fusion des événements de plusieurs sources (FEATURES.md, F3 › Dédoublonnage).
enum CalendarAggregator {
    /// Supprime les doublons (même iCalUID et même début, ou même titre normalisé, début et fin), puis trie par début.
    static func merge(_ sources: [[CalendarEvent]]) -> [CalendarEvent] {
        var seenExternalKeys = Set<String>()
        var seenContentKeys = Set<String>()
        var merged: [CalendarEvent] = []
        for event in sources.joined() {
            let contentKey = "\(normalized(event.title))|\(event.start.timeIntervalSince1970)|\(event.end.timeIntervalSince1970)"
            let externalKey = event.externalID.map { "\($0)|\(event.start.timeIntervalSince1970)" }
            if seenContentKeys.contains(contentKey) || externalKey.map(seenExternalKeys.contains) == true {
                continue
            }
            seenContentKeys.insert(contentKey)
            if let externalKey {
                seenExternalKeys.insert(externalKey)
            }
            merged.append(event)
        }
        return merged.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    private static func normalized(_ title: String) -> String {
        title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Ce que l'Island affiche à partir de l'agenda.
enum CalendarSchedule {
    /// Un événement apparaît en compact une heure avant son début.
    static let lookahead: TimeInterval = 60 * 60

    /// Événement du compact : en cours, sinon le prochain qui commence dans l'heure. Journées entières ignorées.
    static func current(in events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        let timed = events.filter { !$0.isAllDay && !$0.hasEnded(at: now) }
        if let ongoing = timed.filter({ $0.isOngoing(at: now) }).max(by: { $0.start < $1.start }) {
            return ongoing
        }
        return timed.filter { $0.start.timeIntervalSince(now) <= lookahead }.min { $0.start < $1.start }
    }

    /// Prochain événement à venir ou en cours, quel que soit son délai. Journées entières ignorées.
    static func next(in events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        current(in: events, at: now) ?? events.filter { !$0.isAllDay && $0.start > now }.min { $0.start < $1.start }
    }

    /// Événement dont l'alerte doit partir : il commence dans `lead` secondes ou moins et n'a pas encore été signalé.
    static func dueAlert(in events: [CalendarEvent], at now: Date, lead: TimeInterval, alreadyAlerted: Set<String>) -> CalendarEvent? {
        events
            .filter { !$0.isAllDay && !alreadyAlerted.contains($0.id) && $0.start > now && $0.start.timeIntervalSince(now) <= lead }
            .min { $0.start < $1.start }
    }

    /// Prochain instant où le compact ou les alertes changent.
    static func nextBoundary(in events: [CalendarEvent], after now: Date, lead: TimeInterval) -> Date? {
        events
            .filter { !$0.isAllDay }
            .flatMap { [$0.start.addingTimeInterval(-lookahead), $0.start.addingTimeInterval(-lead), $0.start, $0.end] }
            .filter { $0 > now }
            .min()
    }

    /// Événements qui touchent le jour donné : journées entières d'abord, puis par heure de début.
    static func events(on day: Date, in events: [CalendarEvent], calendar: Calendar = .current) -> [CalendarEvent] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return events
            .filter { $0.start < dayEnd && $0.end > dayStart }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start, $0.title) < ($1.isAllDay ? 0 : 1, $1.start, $1.title) }
    }
}
