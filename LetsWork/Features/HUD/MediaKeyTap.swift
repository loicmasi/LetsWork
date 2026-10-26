import AppKit
import os

private let logger = Logger(subsystem: "dev.projects.letswork", category: "hud")

/// Intercepte les touches de volume et de luminosité avant macOS. Un événement absorbé n'est ni appliqué
/// ni affiché par le système : LetsWork l'applique lui-même. Nécessite l'autorisation Accessibilité.
@MainActor
final class MediaKeyTap {
    /// Renvoie `true` pour absorber l'événement.
    typealias Handler = @MainActor (MediaKeyPress) -> Bool

    /// `NX_SYSDEFINED` : événements des touches spéciales, absent de `CGEventType`.
    private static let systemDefinedEventType: UInt32 = 14
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`.
    private static let auxControlButtonsSubtype: Int16 = 8

    /// Diagnostic : `defaults write dev.projects.letswork hudDiagnostics -bool true`.
    /// Journalise les touches spéciales et les touches de fonction, jamais la frappe.
    private static var isDiagnosticEnabled: Bool {
        UserDefaults.standard.bool(forKey: "hudDiagnostics")
    }

    /// F1 à F20 et touches dédiées 144/145.
    private static let functionKeyCodes: Set<Int64> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90, 144, 145,
    ]

    private let handler: Handler
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool { tap != nil }

    /// Échoue sans l'autorisation Accessibilité.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << Self.systemDefinedEventType)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS coupe un tap trop lent ou après certaines saisies : on le réactive aussitôt.
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        case .keyDown, .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            var consumed = false
            if let key = HUDKey(functionKeyCode: keyCode) {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                consumed = handler(MediaKeyPress(key: key, isDown: type == .keyDown, isRepeat: isRepeat, flags: event.flags))
            }
            if Self.isDiagnosticEnabled, Self.functionKeyCodes.contains(keyCode) {
                logger.notice("""
                    Touche de fonction \(keyCode, privacy: .public) \(type == .keyDown ? "appui" : "relâchement", privacy: .public), \
                    modificateurs 0x\(String(event.flags.rawValue, radix: 16), privacy: .public), \
                    source \(event.getIntegerValueField(.eventSourceUnixProcessID), privacy: .public) \
                    → \(consumed ? "absorbée" : "transmise", privacy: .public)
                    """)
            }
            return consumed
        default:
            guard
                type.rawValue == Self.systemDefinedEventType,
                let nsEvent = NSEvent(cgEvent: event),
                nsEvent.subtype.rawValue == Self.auxControlButtonsSubtype
            else { return false }
            let press = MediaKeyPress(systemDefinedData1: nsEvent.data1, flags: event.flags)
            let consumed = press.map(handler) ?? false
            if Self.isDiagnosticEnabled {
                logger.notice("""
                    Touche système \((nsEvent.data1 & 0xFFFF_0000) >> 16, privacy: .public), \
                    état 0x\(String((nsEvent.data1 & 0xFF00) >> 8, radix: 16), privacy: .public), \
                    modificateurs 0x\(String(event.flags.rawValue, radix: 16), privacy: .public), \
                    source \(event.getIntegerValueField(.eventSourceUnixProcessID), privacy: .public) \
                    → \(consumed ? "absorbée" : "transmise", privacy: .public)
                    """)
            }
            return consumed
        }
    }
}

/// Le tap est ajouté à la boucle principale : le rappel s'exécute sur le thread principal.
private func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    // L'événement ne quitte pas le thread principal : assumeIsolated le vérifie à l'exécution.
    nonisolated(unsafe) let mainThreadEvent = event
    let consumed = MainActor.assumeIsolated {
        tap.handle(type: type, event: mainThreadEvent)
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
