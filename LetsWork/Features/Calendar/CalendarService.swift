import AppKit
import Observation
import os

private let logger = Logger(subsystem: "dev.projects.letswork", category: "calendar")

/// Agenda de l'utilisateur sur les 7 prochains jours : accès, filtres, événement du compact et alertes.
@MainActor
@Observable
final class CalendarService {
    static let windowDays = 7
    static let alertLeadChoices = [1, 5, 10, 15]

    private enum Key {
        static let hiddenCalendars = "calendarHiddenIDs"
        static let hidesAllDay = "calendarHidesAllDay"
        static let alertLead = "calendarAlertLeadMinutes"
        static let lastUsedCalendar = "calendarLastUsedForNewEvents"
    }

    private(set) var access: CalendarAccess
    /// Événements affichés : fenêtre d'aujourd'hui à J+7, après filtres.
    private(set) var events: [CalendarEvent] = []
    private(set) var calendars: [CalendarInfo] = []
    /// Événement du compact : en cours, ou qui commence dans l'heure.
    private(set) var upcoming: CalendarEvent?

    var hiddenCalendarIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: Key.hiddenCalendars)
            applyFilters()
        }
    }

    var hidesAllDayEvents: Bool {
        didSet {
            UserDefaults.standard.set(hidesAllDayEvents, forKey: Key.hidesAllDay)
            applyFilters()
        }
    }

    var alertLeadMinutes: Int {
        didSet {
            UserDefaults.standard.set(alertLeadMinutes, forKey: Key.alertLead)
            evaluate()
        }
    }

    @ObservationIgnored var onUpcomingChange: ((CalendarEvent?) -> Void)?
    @ObservationIgnored var onAlert: ((CalendarEvent) -> Void)?
    /// Ouvre la fenêtre « Nouvel événement » pour le jour donné (branché par l'AppDelegate).
    @ObservationIgnored var onCreateEventRequest: ((Date) -> Void)?

    @ObservationIgnored private let providers: [any CalendarProvider]
    @ObservationIgnored private var allEvents: [CalendarEvent] = []
    @ObservationIgnored private var alertedEventIDs: Set<String> = []
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(providers: [any CalendarProvider] = [EventKitProvider()]) {
        self.providers = providers
        access = providers.first?.access ?? .denied
        let defaults = UserDefaults.standard
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: Key.hiddenCalendars) ?? [])
        hidesAllDayEvents = defaults.bool(forKey: Key.hidesAllDay)
        alertLeadMinutes = defaults.object(forKey: Key.alertLead) as? Int ?? 5
    }

    func start() {
        for provider in providers {
            provider.onChange = { [weak self] in
                self?.reload()
            }
        }
        // Changement de jour et sortie de veille : la fenêtre et les délais doivent être recalculés.
        let reloadOn: [(NotificationCenter, Notification.Name)] = [
            (.default, .NSCalendarDayChanged),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
        ]
        for (center, name) in reloadOn {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reload()
                }
            }
            observers.append((center, token))
        }
        reload()
    }

    func stop() {
        tickTask?.cancel()
        reloadTask?.cancel()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
    }

    /// Affiche la demande système si l'accès n'a jamais été demandé.
    func requestAccess() async {
        guard let provider = providers.first else { return }
        access = await provider.requestAccess()
        reload()
    }

    /// Calendriers qui acceptent de nouveaux événements, y compris ceux masqués dans l'Island.
    var writableCalendars: [CalendarInfo] {
        calendars.filter(\.allowsModifications)
    }

    /// Dernier calendrier utilisé, sinon celui proposé par macOS, sinon le premier modifiable.
    var defaultCalendarIDForNewEvents: String? {
        let writableIDs = Set(writableCalendars.map(\.id))
        let candidates = [UserDefaults.standard.string(forKey: Key.lastUsedCalendar), providers.first?.defaultCalendarID]
        return candidates.compactMap { $0 }.first(where: writableIDs.contains) ?? writableCalendars.first?.id
    }

    func requestNewEvent(on day: Date) {
        onCreateEventRequest?(day)
    }

    func createEvent(_ draft: EventDraft) async throws {
        guard let provider = providers.first else { throw CalendarError.calendarUnavailable }
        try await provider.createEvent(draft)
        UserDefaults.standard.set(draft.calendarID, forKey: Key.lastUsedCalendar)
        reload()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Ouvre le lien de visioconférence (l'app native le prend en charge si elle est installée).
    func join(_ event: CalendarEvent) {
        guard let url = event.meetingLink?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func reload() {
        access = providers.first?.access ?? .denied
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            let start = Calendar.current.startOfDay(for: .now)
            guard let end = Calendar.current.date(byAdding: .day, value: Self.windowDays + 1, to: start) else { return }
            var sources: [[CalendarEvent]] = []
            for provider in providers {
                do {
                    sources.append(try await provider.events(in: DateInterval(start: start, end: end)))
                } catch {
                    // Hors ligne ou source en panne : on garde les dernières données de cette source.
                    logger.error("Source calendrier indisponible : \(String(describing: error), privacy: .public)")
                }
            }
            guard !Task.isCancelled else { return }
            calendars = providers.flatMap { $0.calendars() }
            allEvents = CalendarAggregator.merge(sources)
            applyFilters()
        }
    }

    private func applyFilters() {
        events = allEvents.filter { event in
            !hiddenCalendarIDs.contains(event.calendarID) && !(hidesAllDayEvents && event.isAllDay)
        }
        evaluate()
    }

    /// Met à jour l'événement du compact, déclenche l'alerte due et programme le prochain réveil.
    private func evaluate(now: Date = .now) {
        let current = CalendarSchedule.current(in: events, at: now)
        if current != upcoming {
            upcoming = current
            onUpcomingChange?(current)
        }
        let lead = TimeInterval(alertLeadMinutes * 60)
        if let due = CalendarSchedule.dueAlert(in: events, at: now, lead: lead, alreadyAlerted: alertedEventIDs) {
            alertedEventIDs.insert(due.id)
            onAlert?(due)
        }

        tickTask?.cancel()
        // Au plus tard toutes les 5 min, par sécurité ; sinon au prochain changement prévu.
        let wake = min(
            CalendarSchedule.nextBoundary(in: events, after: now, lead: lead) ?? .distantFuture,
            now.addingTimeInterval(5 * 60)
        )
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, wake.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }
}
