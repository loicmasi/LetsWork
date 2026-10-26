import CoreGraphics

/// Dimensions de l'Island pour chaque état, à partir de l'encoche de l'écran courant.
struct IslandMetrics: Equatable {
    /// Taille de la fenêtre transparente dans laquelle l'Island s'anime.
    static let canvasSize = CGSize(width: 640, height: 240)
    static let compactWingWidth: CGFloat = 72
    static let expandedSize = CGSize(width: 520, height: 180)
    /// Marge autour de la forme pour déclencher le survol sans être pixel-perfect.
    static let hoverMargin: CGFloat = 6

    var notch: NotchGeometry

    /// Taille du corps de l'Island, sans les arrondis évasés du haut.
    func size(for state: IslandState) -> CGSize {
        switch state {
        case .closed:
            notch.size
        case .compact:
            CGSize(width: notch.size.width + 2 * Self.compactWingWidth, height: notch.size.height)
        case .expanded:
            CGSize(
                width: max(Self.expandedSize.width, notch.size.width + 2 * Self.compactWingWidth),
                height: max(Self.expandedSize.height, notch.size.height)
            )
        }
    }

    /// Arrondi évasé qui raccorde l'Island au bord de l'écran. Nul à l'état fermé pour se fondre dans l'encoche.
    func topCornerRadius(for state: IslandState) -> CGFloat {
        switch state {
        case .closed: 0
        case .compact: 6
        case .expanded: 12
        }
    }

    func bottomCornerRadius(for state: IslandState) -> CGFloat {
        switch state {
        case .closed: 10
        case .compact: 12
        case .expanded: 26
        }
    }

    /// Zone de survol en coordonnées écran (origine en bas à gauche), ancrée en haut au centre de l'écran.
    func hitZone(for state: IslandState, in screenFrame: CGRect) -> CGRect {
        let size = size(for: state)
        let rect = CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return rect.insetBy(dx: -Self.hoverMargin, dy: -Self.hoverMargin)
    }
}
