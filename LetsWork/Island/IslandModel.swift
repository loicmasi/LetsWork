import Foundation
import Observation

/// État observable de l'Island : applique les délais de survol et l'épinglage au clic.
@MainActor
@Observable
final class IslandModel {
    static let hoverInDelay: Duration = .milliseconds(150)
    static let hoverOutDelay: Duration = .milliseconds(250)

    private(set) var state: IslandState = .closed
    private(set) var metrics: IslandMetrics
    private(set) var activity: IslandActivity?
    private(set) var hud: HUDState?
    private(set) var alert: CalendarEvent?
    private(set) var notification: SystemNotification?
    /// Page affichée à l'état étendu ; conservée d'une ouverture à l'autre.
    private(set) var selectedTab: IslandTab = .home
    /// Jeu affiché dans l'onglet Jeux.
    private(set) var selectedGame: GameKind = .ticTacToe
    /// Parties de l'onglet Jeux, conservées quand l'Island se referme.
    let game = TicTacToeGame()
    let maze = MazeGameController()

    /// Clic sur la notification affichée : le coordinateur la masque et passe à la suivante.
    @ObservationIgnored var onNotificationTap: (() -> Void)?
    /// Une partie de Glouton prend (vrai) ou rend (faux) le clavier ; branché par IslandWindowController.
    @ObservationIgnored var onKeyboardFocusChange: ((Bool) -> Void)?

    @ObservationIgnored private var inputs = IslandInputs()
    @ObservationIgnored private var pendingTransition: Task<Void, Never>?

    init(metrics: IslandMetrics) {
        self.metrics = metrics
        maze.onEngagementChange = { [weak self] engaged in
            self?.mazeEngagementDidChange(engaged)
        }
    }

    func updateMetrics(_ metrics: IslandMetrics) {
        guard metrics != self.metrics else { return }
        self.metrics = metrics
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != inputs.isHovering else { return }
        inputs.isHovering = hovering
        scheduleResolve(after: hovering ? Self.hoverInDelay : Self.hoverOutDelay)
    }

    func togglePinned() {
        inputs.isPinned.toggle()
        if !inputs.isPinned {
            maze.exit()
        }
        resolveNow()
    }

    /// Clic en dehors de l'Island : retire l'épinglage et quitte une partie en cours.
    func dismissPin() {
        maze.exit()
        guard inputs.isPinned else { return }
        inputs.isPinned = false
        resolveNow()
    }

    func setActivity(_ activity: IslandActivity?) {
        guard activity != self.activity else { return }
        self.activity = activity
        inputs.hasActivity = activity != nil
        resolveNow()
    }

    func selectTab(_ tab: IslandTab) {
        if tab != .game {
            maze.exit()
        }
        selectedTab = tab
    }

    func selectGame(_ game: GameKind) {
        if game != .maze {
            maze.exit()
        }
        selectedGame = game
    }

    /// Touche reçue pendant que l'Island a le clavier ; renvoie vrai si la partie l'utilise.
    func handleKey(_ keyCode: UInt16) -> Bool {
        guard maze.isEngaged, state == .expanded, selectedTab == .game, selectedGame == .maze else { return false }
        return maze.handleKey(keyCode)
    }

    /// Pendant une partie, l'Island reste ouverte même si la souris s'éloigne.
    private func mazeEngagementDidChange(_ engaged: Bool) {
        if engaged {
            inputs.isPinned = true
            resolveNow()
        }
        onKeyboardFocusChange?(engaged)
    }

    /// `nil` masque la notification.
    func setNotification(_ notification: SystemNotification?) {
        self.notification = notification
        inputs.isShowingNotification = notification != nil
        resolveNow()
    }

    /// Alerte de batterie faible ; le niveau affiché est lu dans `BatteryService`.
    func setLowBattery(_ showing: Bool) {
        guard showing != inputs.isShowingLowBattery else { return }
        inputs.isShowingLowBattery = showing
        resolveNow()
    }

    /// Indicateur de charge au branchement du chargeur.
    func setCharging(_ showing: Bool) {
        guard showing != inputs.isShowingCharging else { return }
        inputs.isShowingCharging = showing
        resolveNow()
    }

    /// `nil` masque l'alerte de réunion.
    func setAlert(_ event: CalendarEvent?) {
        alert = event
        inputs.isShowingAlert = event != nil
        resolveNow()
    }

    /// `nil` masque le HUD et rend la main à l'état précédent.
    func setHUD(_ hud: HUDState?) {
        self.hud = hud
        inputs.isShowingHUD = hud != nil
        resolveNow()
    }

    func setPeeking(_ peeking: Bool) {
        guard peeking != inputs.isPeeking else { return }
        inputs.isPeeking = peeking
        resolveNow()
    }

    private func scheduleResolve(after delay: Duration) {
        pendingTransition?.cancel()
        pendingTransition = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.resolveNow()
        }
    }

    private func resolveNow() {
        pendingTransition?.cancel()
        pendingTransition = nil
        let next = IslandState.resolve(inputs)
        if next != state {
            state = next
        }
    }
}
