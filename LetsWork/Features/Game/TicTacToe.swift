import Foundation

/// Joueur d'une case : l'utilisateur joue les X, le bot les O.
enum TicTacToeMark: Equatable, Sendable {
    case player
    case bot

    var opponent: TicTacToeMark {
        self == .player ? .bot : .player
    }
}

/// Plateau de 9 cases, numérotées de gauche à droite puis de haut en bas.
struct TicTacToeBoard: Equatable, Sendable {
    static let lines: [[Int]] = [
        [0, 1, 2], [3, 4, 5], [6, 7, 8],
        [0, 3, 6], [1, 4, 7], [2, 5, 8],
        [0, 4, 8], [2, 4, 6],
    ]

    private(set) var cells: [TicTacToeMark?] = Array(repeating: nil, count: 9)

    var winningLine: [Int]? {
        Self.lines.first { line in
            guard let mark = cells[line[0]] else { return false }
            return cells[line[1]] == mark && cells[line[2]] == mark
        }
    }

    var winner: TicTacToeMark? {
        winningLine.flatMap { cells[$0[0]] }
    }

    var emptyCells: [Int] {
        cells.indices.filter { cells[$0] == nil }
    }

    var isOver: Bool {
        winner != nil || emptyCells.isEmpty
    }

    func placing(_ mark: TicTacToeMark, at index: Int) -> TicTacToeBoard {
        var board = self
        board.cells[index] = mark
        return board
    }
}

enum TicTacToeLevel: String, CaseIterable, Identifiable, Sendable {
    case easy
    case medium
    case unbeatable

    var id: Self { self }

    var title: String {
        switch self {
        case .easy: String(localized: "Facile")
        case .medium: String(localized: "Moyen")
        case .unbeatable: String(localized: "Imbattable")
        }
    }

    /// Part des coups joués au mieux ; les autres sont tirés au hasard.
    var bestMoveRate: Double {
        switch self {
        case .easy: 0
        case .medium: 0.7
        case .unbeatable: 1
        }
    }
}

/// Choix du coup du bot : minimax pour le meilleur coup, hasard selon le niveau.
enum TicTacToeBot {
    static func move(on board: TicTacToeBoard, level: TicTacToeLevel, using generator: inout some RandomNumberGenerator) -> Int? {
        let empty = board.emptyCells
        guard !empty.isEmpty, !board.isOver else { return nil }
        if Double.random(in: 0..<1, using: &generator) < level.bestMoveRate {
            return bestMove(on: board, for: .bot)
        }
        return empty.randomElement(using: &generator)
    }

    /// Coup optimal : gagner le plus vite possible, sinon perdre le plus tard possible.
    static func bestMove(on board: TicTacToeBoard, for mark: TicTacToeMark) -> Int? {
        let empty = board.emptyCells
        // Plateau vide : le centre est optimal, inutile d'explorer tout l'arbre.
        if empty.count == 9 {
            return 4
        }
        var best: (index: Int, score: Int)?
        for index in empty {
            let score = -negamax(board.placing(mark, at: index), toMove: mark.opponent, depth: 1)
            if best == nil || score > best!.score {
                best = (index, score)
            }
        }
        return best?.index
    }

    /// Score du point de vue du joueur qui doit jouer : positif s'il gagne, plus fort s'il gagne vite.
    private static func negamax(_ board: TicTacToeBoard, toMove mark: TicTacToeMark, depth: Int) -> Int {
        if let winner = board.winner {
            return winner == mark ? 10 - depth : depth - 10
        }
        let empty = board.emptyCells
        guard !empty.isEmpty else { return 0 }
        return empty.map { -negamax(board.placing(mark, at: $0), toMove: mark.opponent, depth: depth + 1) }.max() ?? 0
    }
}
