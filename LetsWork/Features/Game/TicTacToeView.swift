import SwiftUI

/// Onglet Morpion : le plateau à gauche ; l'état de la partie, le score, le niveau et « Nouvelle partie » à droite.
struct TicTacToeView: View {
    let game: TicTacToeGame
    let notchHeight: CGFloat

    private static let cellSize: CGFloat = 46
    private static let spacing: CGFloat = 6
    private static let playerColor = Color.cyan
    private static let botColor = Color.pink

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            board
            VStack(alignment: .leading, spacing: 10) {
                Text(statusText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .contentTransition(.opacity)
                Text("Vous \(game.score.player) · Bot \(game.score.bot) · Nuls \(game.score.draws)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                levelPicker
                Button("Nouvelle partie", action: game.newGame)
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
        .padding(.top, notchHeight + 6)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: game.board)
    }

    private var board: some View {
        let winningLine = game.board.winningLine ?? []
        return Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        cell(at: row * 3 + column, isWinning: winningLine.contains(row * 3 + column))
                    }
                }
            }
        }
    }

    private func cell(at index: Int, isWinning: Bool) -> some View {
        let mark = game.board.cells[index]
        return Button {
            game.play(at: index)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isWinning ? color(of: mark).opacity(0.3) : .white.opacity(0.08))
                if let mark {
                    Image(systemName: mark == .player ? "xmark" : "circle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(color(of: mark))
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(width: Self.cellSize, height: Self.cellSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(mark != nil || game.status != .playerTurn)
        .accessibilityLabel(accessibilityLabel(for: index, mark: mark))
    }

    private var levelPicker: some View {
        HStack(spacing: 4) {
            ForEach(TicTacToeLevel.allCases) { level in
                let isSelected = level == game.level
                Button {
                    game.level = level
                } label: {
                    Text(level.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Capsule().fill(.white.opacity(isSelected ? 0.16 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statusText: String {
        switch game.status {
        case .playerTurn: String(localized: "À vous de jouer")
        case .botThinking: String(localized: "Le bot réfléchit…")
        case .won(.player): String(localized: "Vous avez gagné !")
        case .won(.bot): String(localized: "Le bot a gagné")
        case .draw: String(localized: "Match nul")
        }
    }

    private var statusColor: Color {
        switch game.status {
        case .won(.player): Self.playerColor
        case .won(.bot): Self.botColor
        default: .white
        }
    }

    private func color(of mark: TicTacToeMark?) -> Color {
        mark == .bot ? Self.botColor : Self.playerColor
    }

    private func accessibilityLabel(for index: Int, mark: TicTacToeMark?) -> String {
        let position = String(localized: "Case \(index + 1)")
        switch mark {
        case .player?: return "\(position), X"
        case .bot?: return "\(position), O"
        case nil: return position
        }
    }
}
