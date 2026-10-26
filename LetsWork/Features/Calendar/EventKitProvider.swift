import EventKit
import Foundation

/// Une source d'événements. EventKit couvre les comptes ajoutés à macOS ; des fournisseurs Google Calendar
/// et Microsoft Graph pourront s'y ajouter pour les comptes absents de macOS (FEATURES.md, F3).
@MainActor
protocol CalendarProvider: AnyObject {
    var access: CalendarAccess { get }
    /// Appelé quand les événements de la source changent.
    var onChange: (() -> Void)? { get set }
    func requestAccess() async -> CalendarAccess
    func calendars() -> [CalendarInfo]
    func events(in interval: DateInterval) async throws -> [CalendarEvent]
}

/// Comptes ajoutés à macOS (iCloud, Google, Exchange, CalDAV), via EventKit.
@MainActor
final class EventKitProvider: CalendarProvider {
    var onChange: (() -> Void)?

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
    }

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        case .writeOnly, .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    func requestAccess() async -> CalendarAccess {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.requestFullAccessToEvents { _, _ in
                continuation.resume()
            }
        }
        // Le magasin doit relire les comptes après l'octroi de l'accès.
        store.reset()
        return access
    }

    func calendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title, color: CalendarColor(cgColor: $0.cgColor)) }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        guard access == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).compactMap(Self.event(from:))
    }

    /// Ignore les événements annulés et ceux que l'utilisateur a refusés.
    private static func event(from event: EKEvent) -> CalendarEvent? {
        guard event.status != .canceled else { return nil }
        if event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined {
            return nil
        }
        let title = event.title.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Sans titre")
        return CalendarEvent(
            id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)",
            externalID: event.calendarItemExternalIdentifier,
            title: title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            color: CalendarColor(cgColor: event.calendar.cgColor),
            location: event.location.flatMap { $0.isEmpty ? nil : $0 },
            meetingLink: MeetingLinkDetector.detect(url: event.url, location: event.location, notes: event.notes)
        )
    }
}
