import CoreGraphics
import Foundation

/// Luminosité des écrans intégrés via le framework privé DisplayServices, chargé dynamiquement.
/// `nil` si le framework ou ses fonctions sont absents : la luminosité reste alors gérée par macOS.
struct DisplayServices {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool

    private let getBrightnessFunction: GetBrightness
    private let setBrightnessFunction: SetBrightness
    private let canChangeBrightnessFunction: CanChangeBrightness

    init?() {
        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
            let get = dlsym(handle, "DisplayServicesGetBrightness"),
            let set = dlsym(handle, "DisplayServicesSetBrightness"),
            let canChange = dlsym(handle, "DisplayServicesCanChangeBrightness")
        else { return nil }
        getBrightnessFunction = unsafeBitCast(get, to: GetBrightness.self)
        setBrightnessFunction = unsafeBitCast(set, to: SetBrightness.self)
        canChangeBrightnessFunction = unsafeBitCast(canChange, to: CanChangeBrightness.self)
    }

    func canChangeBrightness(of display: CGDirectDisplayID) -> Bool {
        canChangeBrightnessFunction(display)
    }

    /// Entre 0 et 1.
    func brightness(of display: CGDirectDisplayID) -> Double? {
        var value: Float = 0
        guard getBrightnessFunction(display, &value) == 0 else { return nil }
        return Double(value)
    }

    func setBrightness(_ value: Double, of display: CGDirectDisplayID) -> Bool {
        setBrightnessFunction(display, Float(value)) == 0
    }
}
