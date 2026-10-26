import SwiftUI

enum GameKind: CaseIterable, Identifiable {
    case ticTacToe
    case maze

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .ticTacToe: "Morpion"
        case .maze: "Glouton"
        }
    }
}

/// Onglet Jeux : le jeu choisi, et le sélecteur Morpion / Glouton dans l'espace à droite de l'encoche.
struct GamesView: View {
    let model: IslandModel
    let notchHeight: CGFloat

    var body: some View {
        Group {
            switch model.selectedGame {
            case .ticTacToe:
                TicTacToeView(game: model.game, notchHeight: notchHeight)
            case .maze:
                MazeGameView(controller: model.maze, notchHeight: notchHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                ForEach(GameKind.allCases) { game in
                    let isSelected = game == model.selectedGame
                    Button {
                        model.selectGame(game)
                    } label: {
                        Text(game.title)
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
            .frame(height: notchHeight)
            .padding(.trailing, 22)
        }
    }
}
