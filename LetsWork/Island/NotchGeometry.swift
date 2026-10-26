import AppKit

/// Taille de l'encoche d'un écran, ou d'une encoche simulée sur un écran qui n'en a pas.
struct NotchGeometry: Equatable {
    static let simulatedWidth: CGFloat = 190
    static let minimumSimulatedHeight: CGFloat = 24

    var size: CGSize
    var hasNotch: Bool

    /// Calcul pur, séparé de `NSScreen` pour être testable.
    static func compute(
        screenWidth: CGFloat,
        safeAreaTop: CGFloat,
        topLeftAreaWidth: CGFloat?,
        topRightAreaWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> NotchGeometry {
        if safeAreaTop > 0, let left = topLeftAreaWidth, let right = topRightAreaWidth {
            return NotchGeometry(size: CGSize(width: screenWidth - left - right, height: safeAreaTop), hasNotch: true)
        }
        let height = max(menuBarHeight, minimumSimulatedHeight)
        return NotchGeometry(size: CGSize(width: simulatedWidth, height: height), hasNotch: false)
    }

    @MainActor
    init(screen: NSScreen) {
        self = Self.compute(
            screenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            topLeftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            topRightAreaWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
    }

    init(size: CGSize, hasNotch: Bool) {
        self.size = size
        self.hasNotch = hasNotch
    }
}
