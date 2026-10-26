import Foundation

enum MazeDirection: CaseIterable, Equatable, Sendable {
    case up
    case down
    case left
    case right

    var delta: (x: Int, y: Int) {
        switch self {
        case .up: (0, -1)
        case .down: (0, 1)
        case .left: (-1, 0)
        case .right: (1, 0)
        }
    }

    var opposite: MazeDirection {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }
}

struct MazePoint: Hashable, Sendable {
    var x: Int
    var y: Int
}

enum MazeTile: Equatable, Sendable {
    case wall
    case pellet
    case power
    case empty
}

/// Comportement d'un fantôme quand il n'a pas peur.
enum GhostBehavior: Equatable, Sendable {
    /// Vise la case du glouton.
    case chase
    /// Vise quatre cases devant le glouton.
    case ambush
    /// Erre au hasard.
    case wander
}

struct Ghost: Equatable, Sendable {
    var position: MazePoint
    var direction: MazeDirection = .left
    let home: MazePoint
    let behavior: GhostBehavior
    var isFrightened = false
    /// Délai avant de repartir après avoir été mangé.
    var respawnTicks = 0
    /// Vrai si le dernier déplacement est passé par le tunnel (pas d'animation de glissement).
    var didWrap = false
}

/// Jeu de labyrinthe à la Pac-Man, entièrement déterministe hors tirages aléatoires : un appel à `step` avance d'un pas.
struct MazeGame: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case playing
        case gameOver
    }

    /// `#` mur, `.` pastille, `o` super-pastille, `P` départ du glouton, `G` départ d'un fantôme, espace vide.
    /// La ligne du milieu est ouverte aux deux bouts : c'est un tunnel.
    static let standardLayout = [
        "###################",
        "#o.......#.......o#",
        "#.##.###.#.###.##.#",
        "#.................#",
        "#.##.#.#####.#.##.#",
        " ....#..GGG..#.... ",
        "#.##.#.#####.#.##.#",
        "#........P........#",
        "#.##.###.#.###.##.#",
        "#o.......#.......o#",
        "###################",
    ]

    static let startingLives = 3
    /// Durée de la peur des fantômes après une super-pastille, en pas.
    static let frightenedDuration = 40
    /// Pause après une vie perdue ou un niveau terminé, en pas.
    static let freezeDuration = 6
    static let ghostBehaviors: [GhostBehavior] = [.chase, .ambush, .wander]

    let layout: [String]
    let width: Int
    let height: Int
    private(set) var tiles: [[MazeTile]]
    private let pacStart: MazePoint

    private(set) var pac: MazePoint
    private(set) var pacDirection: MazeDirection?
    private(set) var wantedDirection: MazeDirection?
    private(set) var pacDidWrap = false
    private(set) var ghosts: [Ghost]
    private(set) var score = 0
    private(set) var lives = MazeGame.startingLives
    private(set) var level = 1
    private(set) var phase = Phase.playing
    private(set) var tick = 0
    private(set) var frightenedTicks = 0
    private(set) var freezeTicks = 0
    private var ghostCombo = 0

    init(layout: [String] = MazeGame.standardLayout) {
        self.layout = layout
        height = layout.count
        width = layout.map(\.count).max() ?? 0
        var pacStart = MazePoint(x: 0, y: 0)
        var ghostStarts: [MazePoint] = []
        tiles = Self.parse(layout, width: width)
        for (y, row) in layout.enumerated() {
            for (x, character) in row.enumerated() {
                if character == "P" { pacStart = MazePoint(x: x, y: y) }
                if character == "G" { ghostStarts.append(MazePoint(x: x, y: y)) }
            }
        }
        self.pacStart = pacStart
        pac = pacStart
        ghosts = ghostStarts.enumerated().map { index, start in
            Ghost(position: start, home: start, behavior: Self.ghostBehaviors[index % Self.ghostBehaviors.count])
        }
    }

    var pelletsLeft: Int {
        tiles.joined().filter { $0 == .pellet || $0 == .power }.count
    }

    func tile(at point: MazePoint) -> MazeTile {
        guard (0..<height).contains(point.y), (0..<width).contains(point.x) else { return .wall }
        return tiles[point.y][point.x]
    }

    /// Case voisine dans une direction ; les bords ouverts mènent de l'autre côté (tunnel).
    func neighbor(of point: MazePoint, toward direction: MazeDirection) -> (point: MazePoint, wrapped: Bool)? {
        var next = MazePoint(x: point.x + direction.delta.x, y: point.y + direction.delta.y)
        var wrapped = false
        if next.x < 0 {
            next.x = width - 1
            wrapped = true
        } else if next.x >= width {
            next.x = 0
            wrapped = true
        }
        return tile(at: next) == .wall ? nil : (next, wrapped)
    }

    /// Mémorise la direction voulue ; elle est prise dès que le passage est libre.
    mutating func steer(_ direction: MazeDirection) {
        wantedDirection = direction
    }

    mutating func step(using generator: inout some RandomNumberGenerator) {
        guard phase == .playing else { return }
        if freezeTicks > 0 {
            freezeTicks -= 1
            return
        }
        tick += 1

        let pacBefore = pac
        movePac()
        if resolveCollisions(pacBefore: pacBefore, ghostsBefore: ghosts.map(\.position)) { return }

        let ghostsBefore = ghosts.map(\.position)
        moveGhosts(using: &generator)
        if resolveCollisions(pacBefore: pac, ghostsBefore: ghostsBefore) { return }

        if frightenedTicks > 0 {
            frightenedTicks -= 1
            if frightenedTicks == 0 {
                for index in ghosts.indices {
                    ghosts[index].isFrightened = false
                }
            }
        }
        if pelletsLeft == 0 {
            nextLevel()
        }
    }

    // MARK: - Glouton

    private mutating func movePac() {
        pacDidWrap = false
        if let wanted = wantedDirection, neighbor(of: pac, toward: wanted) != nil {
            pacDirection = wanted
        }
        guard let direction = pacDirection, let next = neighbor(of: pac, toward: direction) else { return }
        pac = next.point
        pacDidWrap = next.wrapped
        switch tiles[pac.y][pac.x] {
        case .pellet:
            score += 10
            tiles[pac.y][pac.x] = .empty
        case .power:
            score += 50
            tiles[pac.y][pac.x] = .empty
            frightenedTicks = Self.frightenedDuration
            ghostCombo = 0
            for index in ghosts.indices where ghosts[index].respawnTicks == 0 {
                ghosts[index].isFrightened = true
                ghosts[index].direction = ghosts[index].direction.opposite
            }
        case .wall, .empty:
            break
        }
    }

    // MARK: - Fantômes

    private mutating func moveGhosts(using generator: inout some RandomNumberGenerator) {
        for index in ghosts.indices {
            ghosts[index].didWrap = false
            if ghosts[index].respawnTicks > 0 {
                ghosts[index].respawnTicks -= 1
                continue
            }
            // Fantômes un peu plus lents au début, deux fois plus lents quand ils ont peur.
            if ghosts[index].isFrightened, tick % 2 == 0 { continue }
            if !ghosts[index].isFrightened, level < 3, tick % 5 == 0 { continue }
            let direction = chooseDirection(for: ghosts[index], using: &generator)
            if let next = neighbor(of: ghosts[index].position, toward: direction) {
                ghosts[index].position = next.point
                ghosts[index].direction = direction
                ghosts[index].didWrap = next.wrapped
            }
        }
    }

    /// Pas de demi-tour sauf impasse ; vers la cible au plus court à vol d'oiseau, au hasard s'il a peur ou erre.
    private func chooseDirection(for ghost: Ghost, using generator: inout some RandomNumberGenerator) -> MazeDirection {
        let open = MazeDirection.allCases.filter { neighbor(of: ghost.position, toward: $0) != nil }
        let forward = open.filter { $0 != ghost.direction.opposite }
        let candidates = forward.isEmpty ? open : forward
        guard !candidates.isEmpty else { return ghost.direction }
        if ghost.isFrightened || ghost.behavior == .wander {
            return candidates.randomElement(using: &generator) ?? ghost.direction
        }
        let target = target(for: ghost)
        return candidates.min { lhs, rhs in
            distance(from: neighbor(of: ghost.position, toward: lhs)!.point, to: target)
                < distance(from: neighbor(of: ghost.position, toward: rhs)!.point, to: target)
        } ?? ghost.direction
    }

    private func target(for ghost: Ghost) -> MazePoint {
        guard ghost.behavior == .ambush, let direction = pacDirection else { return pac }
        return MazePoint(x: pac.x + direction.delta.x * 4, y: pac.y + direction.delta.y * 4)
    }

    private func distance(from a: MazePoint, to b: MazePoint) -> Int {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }

    // MARK: - Collisions, vies et niveaux

    /// Gère une rencontre (même case, ou croisement en sens inverse) ; renvoie vrai si le tour s'arrête là.
    private mutating func resolveCollisions(pacBefore: MazePoint, ghostsBefore: [MazePoint]) -> Bool {
        for index in ghosts.indices {
            let ghost = ghosts[index]
            let sameCell = ghost.position == pac
            let crossed = ghost.position == pacBefore && ghostsBefore[index] == pac
            guard sameCell || crossed, ghost.respawnTicks == 0 else { continue }
            if ghost.isFrightened {
                ghostCombo += 1
                score += 200 * (1 << (ghostCombo - 1))
                ghosts[index].position = ghost.home
                ghosts[index].isFrightened = false
                ghosts[index].respawnTicks = Self.freezeDuration
                ghosts[index].didWrap = true
            } else {
                loseLife()
                return true
            }
        }
        return false
    }

    private mutating func loseLife() {
        lives -= 1
        if lives <= 0 {
            phase = .gameOver
            return
        }
        resetPositions()
    }

    private mutating func nextLevel() {
        level += 1
        tiles = Self.parse(layout, width: width)
        resetPositions()
    }

    private mutating func resetPositions() {
        pac = pacStart
        pacDirection = nil
        wantedDirection = nil
        pacDidWrap = true
        frightenedTicks = 0
        for index in ghosts.indices {
            ghosts[index].position = ghosts[index].home
            ghosts[index].direction = .left
            ghosts[index].isFrightened = false
            ghosts[index].respawnTicks = 0
            ghosts[index].didWrap = true
        }
        freezeTicks = Self.freezeDuration
    }

    private static func parse(_ layout: [String], width: Int) -> [[MazeTile]] {
        layout.map { row in
            let characters = Array(row.padding(toLength: width, withPad: " ", startingAt: 0))
            return characters.map { character in
                switch character {
                case "#": .wall
                case ".": .pellet
                case "o": .power
                default: .empty
                }
            }
        }
    }
}
