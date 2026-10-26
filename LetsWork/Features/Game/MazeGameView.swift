import SwiftUI

/// Glouton : le labyrinthe à gauche ; score, vies, état de la partie et commandes à droite.
struct MazeGameView: View {
    let controller: MazeGameController
    let notchHeight: CGFloat

    private static let cell: CGFloat = 16
    private static let wallColor = Color(red: 0.3, green: 0.36, blue: 0.95)
    private static let pelletColor = Color(red: 1, green: 0.85, blue: 0.7)
    private static let pacColor = Color.yellow
    private static let ghostColors: [Color] = [.red, .purple, .green]
    private static let frightenedColor = Color(red: 0.25, green: 0.35, blue: 1)

    var body: some View {
        let game = controller.game
        HStack(alignment: .top, spacing: 24) {
            board(game)
                .frame(width: CGFloat(game.width) * Self.cell, height: CGFloat(game.height) * Self.cell)
                .contentShape(Rectangle())
                // Un clic sur le plateau lance la partie, et ne referme pas l'Island épinglée.
                .onTapGesture {
                    if !controller.isEngaged {
                        controller.start()
                    }
                }
            sidePanel(game)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, notchHeight + 8)
        .onDisappear {
            controller.pause()
        }
    }

    // MARK: - Plateau

    private func board(_ game: MazeGame) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for y in 0..<game.height {
                    for x in 0..<game.width {
                        let rect = CGRect(x: CGFloat(x) * Self.cell, y: CGFloat(y) * Self.cell, width: Self.cell, height: Self.cell)
                        switch game.tile(at: MazePoint(x: x, y: y)) {
                        case .wall:
                            context.fill(Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 4), with: .color(Self.wallColor.opacity(0.85)))
                        case .pellet:
                            context.fill(Path(ellipseIn: rect.insetBy(dx: 6, dy: 6)), with: .color(Self.pelletColor))
                        case .power:
                            context.fill(Path(ellipseIn: rect.insetBy(dx: 3, dy: 3)), with: .color(Self.pelletColor))
                        case .empty:
                            break
                        }
                    }
                }
            }
            ForEach(Array(game.ghosts.enumerated()), id: \.offset) { index, ghost in
                ghostView(ghost, color: Self.ghostColors[index % Self.ghostColors.count], game: game)
                    .frame(width: Self.cell, height: Self.cell)
                    .position(center(of: ghost.position))
                    .animation(ghost.didWrap ? nil : .linear(duration: tickSeconds), value: ghost.position)
            }
            PacShape(mouth: .degrees(game.tick % 2 == 0 ? 55 : 10))
                .fill(Self.pacColor)
                .frame(width: Self.cell - 2, height: Self.cell - 2)
                .rotationEffect(rotation(for: game.pacDirection))
                .position(center(of: game.pac))
                .animation(game.pacDidWrap ? nil : .linear(duration: tickSeconds), value: game.pac)
        }
    }

    private func ghostView(_ ghost: Ghost, color: Color, game: MazeGame) -> some View {
        let blinking = ghost.isFrightened && game.frightenedTicks < 10 && game.tick % 2 == 0
        let bodyColor = ghost.isFrightened ? (blinking ? .white : Self.frightenedColor) : color
        return ZStack {
            if ghost.respawnTicks == 0 {
                GhostShape()
                    .fill(bodyColor)
            }
            GhostEyes(direction: ghost.direction, isFrightened: ghost.isFrightened)
        }
        .padding(1)
    }

    // MARK: - Panneau latéral

    private func sidePanel(_ game: MazeGame) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Glouton")
                .font(.title3.weight(.semibold))
            Text("Score \(game.score) · Record \(controller.bestScore)")
                .font(.callout.monospacedDigit())
            HStack(spacing: 6) {
                ForEach(0..<max(game.lives, 0), id: \.self) { _ in
                    PacShape(mouth: .degrees(50))
                        .fill(Self.pacColor)
                        .frame(width: 12, height: 12)
                }
                Text("Niveau \(game.level)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            Text(statusText(game))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if game.phase == .gameOver {
                    Button("Rejouer", action: controller.newGame)
                } else if !controller.isEngaged {
                    Button("Jouer", action: controller.start)
                } else {
                    Button(controller.isRunning ? "Pause" : "Reprendre", action: controller.togglePause)
                    Button("Quitter", action: controller.exit)
                }
            }
            .controlSize(.small)
        }
    }

    private func statusText(_ game: MazeGame) -> String {
        if game.phase == .gameOver {
            return String(localized: "Partie terminée. Entrée pour rejouer.")
        }
        if !controller.isEngaged {
            return String(localized: "Mangez toutes les pastilles sans vous faire attraper. Les grosses pastilles effraient les fantômes.")
        }
        if !controller.isRunning {
            return String(localized: "En pause. Espace ou une flèche pour reprendre.")
        }
        return String(localized: "Flèches : diriger · Espace : pause · Échap : quitter")
    }

    // MARK: - Géométrie

    private var tickSeconds: Double {
        Double(MazeGameController.tick.components.attoseconds) / 1e18 + Double(MazeGameController.tick.components.seconds)
    }

    private func center(of point: MazePoint) -> CGPoint {
        CGPoint(x: (CGFloat(point.x) + 0.5) * Self.cell, y: (CGFloat(point.y) + 0.5) * Self.cell)
    }

    private func rotation(for direction: MazeDirection?) -> Angle {
        switch direction {
        case .down?: .degrees(90)
        case .left?: .degrees(180)
        case .up?: .degrees(270)
        case .right?, nil: .zero
        }
    }
}

/// Disque avec une bouche ouverte vers la droite.
private struct PacShape: Shape {
    var mouth: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: min(rect.width, rect.height) / 2,
            startAngle: mouth / 2,
            endAngle: .degrees(360) - mouth / 2,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// Fantôme : dôme en haut, trois festons en bas.
private struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        let scallop = rect.width / 3
        for index in 0..<3 {
            let endX = rect.maxX - scallop * CGFloat(index + 1)
            path.addQuadCurve(
                to: CGPoint(x: endX, y: rect.maxY),
                control: CGPoint(x: endX + scallop / 2, y: rect.maxY - scallop * 0.7)
            )
        }
        path.closeSubpath()
        return path
    }
}

/// Yeux qui regardent dans la direction du déplacement ; petits points quand le fantôme a peur.
private struct GhostEyes: View {
    let direction: MazeDirection
    let isFrightened: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            let look = CGPoint(x: CGFloat(direction.delta.x) * size * 0.06, y: CGFloat(direction.delta.y) * size * 0.06)
            ForEach([0.32, 0.68], id: \.self) { fraction in
                let center = CGPoint(x: size * fraction, y: size * 0.42)
                if isFrightened {
                    Circle()
                        .fill(.white)
                        .frame(width: size * 0.14, height: size * 0.14)
                        .position(center)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: size * 0.28, height: size * 0.28)
                        .position(center)
                    Circle()
                        .fill(Color(red: 0.1, green: 0.2, blue: 0.8))
                        .frame(width: size * 0.13, height: size * 0.13)
                        .position(x: center.x + look.x, y: center.y + look.y)
                }
            }
        }
    }
}
