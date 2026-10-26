import Foundation

/// Réaction de l'Island à un changement d'état de lecture.
enum MediaTransition: Equatable {
    case playing(isNewTrack: Bool)
    case stopped

    init(from previous: NowPlaying?, to current: NowPlaying?) {
        guard let current, current.isPlaying else {
            self = .stopped
            return
        }
        self = .playing(isNewTrack: previous?.trackIdentity != current.trackIdentity)
    }
}

/// Décide de ce que l'Island affiche selon les activités en cours (FEATURES.md, F0 › Arbitrage).
/// Activité de fond : la lecture en cours, sinon la réunion en cours ou imminente.
@MainActor
final class ActivityCoordinator {
    static let trackChangePeekDuration: Duration = .seconds(3)
    static let playbackEndGrace: Duration = .seconds(5)
    /// Durée d'affichage du HUD après la dernière pression.
    static let hudDuration: Duration = .milliseconds(1500)
    /// Durée d'affichage de l'alerte de réunion, sauf clic.
    static let alertDuration: Duration = .seconds(10)
    /// Durée d'affichage d'une notification ; les suivantes attendent leur tour.
    static let notificationDuration: Duration = .seconds(5)

    private let island: IslandModel
    private var isMediaActive = false
    private var calendarEvent: CalendarEvent?
    private var peekTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?
    private var hudTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var pendingNotifications: [SystemNotification] = []

    init(island: IslandModel, media: MediaService, hud: HUDService, calendar: CalendarService, notifications: NotificationService) {
        self.island = island
        media.onChange = { [weak self] previous, current in
            self?.mediaDidChange(from: previous, to: current)
        }
        hud.onShow = { [weak self] state in
            self?.showHUD(state)
        }
        calendar.onUpcomingChange = { [weak self] event in
            self?.calendarDidChange(event)
        }
        calendar.onAlert = { [weak self] event in
            self?.showAlert(event)
        }
        notifications.onNotification = { [weak self] notification in
            self?.showNotification(notification)
        }
        island.onNotificationTap = { [weak self] in
            self?.dismissNotification()
        }
    }

    /// Affiche la notification, ou la met en file si une autre est déjà affichée.
    func showNotification(_ notification: SystemNotification) {
        guard island.notification == nil else {
            pendingNotifications.append(notification)
            return
        }
        island.setNotification(notification)
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.notificationDuration)
            guard !Task.isCancelled else { return }
            self?.dismissNotification()
        }
    }

    /// Masque la notification affichée (délai écoulé ou clic) et passe à la suivante.
    func dismissNotification() {
        notificationTask?.cancel()
        island.setNotification(nil)
        if !pendingNotifications.isEmpty {
            showNotification(pendingNotifications.removeFirst())
        }
    }

    /// Chaque pression relance le délai avant que l'Island revienne à son état précédent.
    func showHUD(_ state: HUDState) {
        island.setHUD(state)
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hudDuration)
            guard !Task.isCancelled else { return }
            self?.island.setHUD(nil)
        }
    }

    func mediaDidChange(from previous: NowPlaying?, to current: NowPlaying?) {
        switch MediaTransition(from: previous, to: current) {
        case .playing(let isNewTrack):
            graceTask?.cancel()
            graceTask = nil
            isMediaActive = true
            updateActivity()
            if isNewTrack {
                peek()
            }
        case .stopped:
            // Pause ou fin de lecture : l'Island reste en compact quelques secondes avant de passer à la suite.
            guard isMediaActive, graceTask == nil else { return }
            graceTask = Task { [weak self] in
                try? await Task.sleep(for: Self.playbackEndGrace)
                guard !Task.isCancelled, let self else { return }
                self.isMediaActive = false
                self.updateActivity()
                self.graceTask = nil
            }
        }
    }

    func calendarDidChange(_ event: CalendarEvent?) {
        calendarEvent = event
        updateActivity()
    }

    /// L'alerte disparaît seule après quelques secondes, ou au clic sur l'Island.
    func showAlert(_ event: CalendarEvent) {
        island.setAlert(event)
        alertTask?.cancel()
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: Self.alertDuration)
            guard !Task.isCancelled else { return }
            self?.island.setAlert(nil)
        }
    }

    private func updateActivity() {
        if isMediaActive {
            island.setActivity(.media)
        } else if calendarEvent != nil {
            island.setActivity(.calendar)
        } else {
            island.setActivity(nil)
        }
    }

    private func peek() {
        peekTask?.cancel()
        island.setPeeking(true)
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: Self.trackChangePeekDuration)
            guard !Task.isCancelled else { return }
            self?.island.setPeeking(false)
        }
    }
}
