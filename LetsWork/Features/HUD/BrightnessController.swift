import CoreGraphics

/// Luminosité de l'écran intégré, seulement quand c'est l'écran principal (FEATURES.md, F2).
@MainActor
final class BrightnessController {
    private let displayServices: DisplayServices

    init?() {
        guard let displayServices = DisplayServices() else { return nil }
        self.displayServices = displayServices
    }

    /// Écran que les touches de luminosité doivent régler, ou `nil` pour laisser faire macOS.
    var targetDisplay: CGDirectDisplayID? {
        let main = CGMainDisplayID()
        guard CGDisplayIsBuiltin(main) != 0, displayServices.canChangeBrightness(of: main) else { return nil }
        return main
    }

    /// Applique la touche et renvoie le nouveau niveau, ou `nil` si l'écran n'est pas réglable.
    func apply(_ key: HUDKey, fine: Bool) -> Double? {
        guard
            let display = targetDisplay,
            let current = displayServices.brightness(of: display)
        else { return nil }
        let step = fine ? LevelStep.fine : LevelStep.normal
        let level = LevelStep.next(from: current, up: key == .brightnessUp, step: step)
        guard displayServices.setBrightness(level, of: display) else { return nil }
        return level
    }
}
