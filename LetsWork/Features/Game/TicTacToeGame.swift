import Foundation
import Observation

/// Partie de morpion de l'onglet du même nom ; elle continue quand l'Island se referme.
@MainActor
@Observable
final class TicTacToeGame {
    enum Status: Equatable {
        case playerTurn
        case botThinking
        case won(TicTacToeMark)
        case draw
    }

    struct Score: Equatable {
        var player = 0
        var bot = 0
        var draws = 0
    }

    static let levelKey = "ticTacToeLevel"
    /// Petit temps de réflexion du bot, pour que son coup se voie.
    static let botDelay: Duration = .milliseconds(450)

    private(set) var board = TicTacToeBoard()
    private(set) var turn: TicTacToeMark = .player
    private(set) var score = Score()

    var level: TicTacToeLevel {
        didSet {
            UserDefaults.standard.set(level.rawValue, forKey: Self.levelKey)
        }
    }

    @ObservationIgnored private var starter: TicTacToeMark = .player
    @ObservationIgnored private var botTask: Task<Void, Never>?
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()

    init() {
        level = UserDefaults.standard.string(forKey: Self.levelKey).flatMap(TicTacToeLevel.init(rawValue:)) ?? .medium
    }

    var status: Status {
        if let winner = board.winner { return .won(winner) }
        if board.isOver { return .draw }
        return turn == .player ? .playerTurn : .botThinking
    }

    func play(at index: Int) {
        guard turn == .player, !board.isOver, board.cells[index] == nil else { return }
        board = board.placing(.player, at: index)
        finishTurn()
    }

    /// Nouvelle partie ; le premier joueur alterne d'une partie à l'autre.
    func newGame() {
        botTask?.cancel()
        board = TicTacToeBoard()
        starter = starter.opponent
        turn = starter
        if turn == .bot {
            scheduleBotMove()
        }
    }

    private func finishTurn() {
        if board.isOver {
            switch board.winner {
            case .player?: score.player += 1
            case .bot?: score.bot += 1
            case nil: score.draws += 1
            }
            return
        }
        turn = turn.opponent
        if turn == .bot {
            scheduleBotMove()
        }
    }

    private func scheduleBotMove() {
        botTask?.cancel()
        botTask = Task { [weak self] in
            try? await Task.sleep(for: Self.botDelay)
            guard !Task.isCancelled, let self, self.turn == .bot else { return }
            guard let index = TicTacToeBot.move(on: self.board, level: self.level, using: &self.generator) else { return }
            self.board = self.board.placing(.bot, at: index)
            self.finishTurn()
        }
    }
}
