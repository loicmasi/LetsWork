import Foundation
import Observation

/// Partie de Glouton : boucle de jeu, touches, pause. La boucle ne tourne que pendant la partie.
@MainActor
@Observable
final class MazeGameController {
    static let bestScoreKey = "mazeBestScore"
    /// Durée d'un pas : le glouton avance d'une case par pas.
    static let tick: Duration = .milliseconds(160)

    private(set) var game = MazeGame()
    private(set) var isRunning = false
    /// Vrai entre « Jouer » et la sortie (Échap, clic à côté, autre onglet) : l'Island garde alors le clavier.
    private(set) var isEngaged = false
    private(set) var bestScore = UserDefaults.standard.integer(forKey: MazeGameController.bestScoreKey)

    /// Prévient l'Island quand la partie prend ou rend le clavier.
    @ObservationIgnored var onEngagementChange: ((Bool) -> Void)?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()

    func start() {
        if game.phase == .gameOver {
            game = MazeGame()
        }
        setEngaged(true)
        resume()
    }

    func newGame() {
        pause()
        game = MazeGame()
        start()
    }

    func togglePause() {
        isRunning ? pause() : resume()
    }

    /// Met la partie en pause sans rendre le clavier (l'Island est momentanément masquée par un HUD, par exemple).
    func pause() {
        loop?.cancel()
        loop = nil
        isRunning = false
    }

    /// Quitte la partie : pause et clavier rendu à l'app au premier plan.
    func exit() {
        pause()
        setEngaged(false)
    }

    /// Flèches pour diriger, Espace pour la pause, Échap pour quitter, Entrée pour rejouer. Renvoie vrai si la touche est utilisée.
    func handleKey(_ keyCode: UInt16) -> Bool {
        let directions: [UInt16: MazeDirection] = [123: .left, 124: .right, 125: .down, 126: .up]
        if let direction = directions[keyCode] {
            game.steer(direction)
            if !isRunning, game.phase == .playing {
                resume()
            }
            return true
        }
        switch keyCode {
        case 49:
            togglePause()
            return true
        case 53:
            exit()
            return true
        case 36:
            if game.phase == .gameOver {
                newGame()
            }
            return true
        default:
            return false
        }
    }

    private func resume() {
        guard !isRunning, game.phase == .playing else { return }
        isRunning = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                guard !Task.isCancelled, let self else { return }
                self.advance()
            }
        }
    }

    private func advance() {
        game.step(using: &generator)
        if game.score > bestScore {
            bestScore = game.score
            UserDefaults.standard.set(bestScore, forKey: Self.bestScoreKey)
        }
        if game.phase == .gameOver {
            pause()
        }
    }

    private func setEngaged(_ engaged: Bool) {
        guard engaged != isEngaged else { return }
        isEngaged = engaged
        onEngagementChange?(engaged)
    }
}
