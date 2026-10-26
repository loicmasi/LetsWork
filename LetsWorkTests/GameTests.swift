import Testing
@testable import LetsWork

/// Générateur déterministe (SplitMix64) pour rejouer les coups au hasard.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private func board(_ moves: [(Int, TicTacToeMark)]) -> TicTacToeBoard {
    moves.reduce(TicTacToeBoard()) { $0.placing($1.1, at: $1.0) }
}

struct TicTacToeBoardTests {
    @Test(arguments: TicTacToeBoard.lines)
    func detectsEveryLine(line: [Int]) {
        let won = board(line.map { ($0, .bot) })
        #expect(won.winner == .bot)
        #expect(won.winningLine == line)
        #expect(won.isOver)
    }

    @Test func detectsADraw() {
        // X O X / X O O / O X X
        let full = board([
            (0, .player), (1, .bot), (2, .player),
            (3, .player), (4, .bot), (5, .bot),
            (6, .bot), (7, .player), (8, .player),
        ])
        #expect(full.winner == nil)
        #expect(full.isOver)
    }
}

struct TicTacToeBotTests {
    @Test func takesTheWinningMove() {
        let position = board([(0, .bot), (1, .bot), (3, .player), (4, .player)])
        #expect(TicTacToeBot.bestMove(on: position, for: .bot) == 2)
    }

    @Test func blocksThePlayer() {
        let position = board([(0, .player), (1, .player), (4, .bot)])
        #expect(TicTacToeBot.bestMove(on: position, for: .bot) == 2)
    }

    @Test func opensInTheCenter() {
        #expect(TicTacToeBot.bestMove(on: TicTacToeBoard(), for: .bot) == 4)
    }

    /// Essaie toutes les parties possibles du joueur contre le bot imbattable.
    @Test func unbeatableNeverLoses() throws {
        func playerCanWin(_ position: TicTacToeBoard) -> Bool {
            for move in position.emptyCells {
                let afterPlayer = position.placing(.player, at: move)
                if afterPlayer.winner == .player { return true }
                if afterPlayer.isOver { continue }
                guard let reply = TicTacToeBot.bestMove(on: afterPlayer, for: .bot) else { continue }
                let afterBot = afterPlayer.placing(.bot, at: reply)
                if !afterBot.isOver, playerCanWin(afterBot) { return true }
            }
            return false
        }
        #expect(!playerCanWin(TicTacToeBoard()))
        let opening = try #require(TicTacToeBot.bestMove(on: TicTacToeBoard(), for: .bot))
        #expect(!playerCanWin(TicTacToeBoard().placing(.bot, at: opening)))
    }

    @Test func easyPlaysAnyEmptyCell() {
        var generator = SeededGenerator(state: 42)
        let position = board([(0, .player), (4, .bot), (8, .player)])
        for _ in 0..<20 {
            let move = TicTacToeBot.move(on: position, level: .easy, using: &generator)
            #expect(move.map(position.emptyCells.contains) == true)
        }
    }

    @Test func noMoveOnAFinishedBoard() {
        var generator = SeededGenerator(state: 1)
        let won = board([(0, .player), (1, .player), (2, .player)])
        #expect(TicTacToeBot.move(on: won, level: .unbeatable, using: &generator) == nil)
    }
}

@MainActor
struct TicTacToeGameTests {
    @Test func botAnswersThePlayer() async throws {
        let game = TicTacToeGame()
        #expect(game.status == .playerTurn)
        game.play(at: 0)
        #expect(game.status == .botThinking)
        game.play(at: 1)
        #expect(game.board.cells[1] == nil, "pas de coup pendant le tour du bot")
        try await Task.sleep(for: TicTacToeGame.botDelay + .milliseconds(300))
        #expect(game.board.emptyCells.count == 7)
        #expect(game.status == .playerTurn)
    }

    @Test func starterAlternatesBetweenGames() async throws {
        let game = TicTacToeGame()
        game.newGame()
        #expect(game.status == .botThinking)
        try await Task.sleep(for: TicTacToeGame.botDelay + .milliseconds(300))
        #expect(game.board.emptyCells.count == 8)
        game.newGame()
        #expect(game.status == .playerTurn)
        #expect(game.board.emptyCells.count == 9)
    }
}
